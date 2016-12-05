import Foundation
import LLVM_C
import LLVM
import Parse
import AST
import SemanticAnalysis
import IRGen

#if os(Linux)
typealias Process = Task
#endif

open class Driver {
    public var outputStream: TextOutputStream
    public let typeChecker: TypeChecker
    public let irGenerator: IRGenerator
    public var emitInLLVMFormat: Bool
    private let targetMachine: LLVM.TargetMachine
    public var module: LLVM.Module!

    public init(outputStream: TextOutputStream = Stdout(), allowRedefinitions: Bool = false,
                using irGenerator: IRGenerator = IRGenerator()) {
        LLVMInitializeNativeTarget()
        LLVMInitializeNativeAsmPrinter()
        LLVMInitializeNativeAsmParser()

        self.outputStream = outputStream
        self.typeChecker = TypeChecker(allowRedefinitions: allowRedefinitions)
        self.irGenerator = irGenerator
        self.emitInLLVMFormat = false

        let target = try! LLVM.Target(fromTriple: LLVM.defaultTargetTriple)
        targetMachine = LLVM.TargetMachine(target: target, targetTriple: LLVM.defaultTargetTriple,
                                           cpu: "generic", features: "", optLevel: LLVMCodeGenLevelNone)
    }

    public func compileAndExecute(inputFile: String, stdoutPipe: Pipe? = nil) throws -> Int32? {
        return try compileAndExecute(inputFiles: [inputFile], stdoutPipe: stdoutPipe)
    }

    /// Returns the exit status of the executed program on successful completion, or `nil` if
    /// the compiled program was not executed, e.g. because the compilation didn't succeed.
    public func compileAndExecute(inputFiles: [String], stdoutPipe: Pipe? = nil) throws -> Int32? {
        if !compile(inputFiles: inputFiles) { return nil }
        let moduleName = determineModuleName(for: inputFiles)

        let linkProcess = Process()
        linkProcess.launchPath = "/usr/bin/env"
        linkProcess.arguments = ["cc", moduleName + ".o", "-o", moduleName + ".out"]
        linkProcess.launch()
        linkProcess.waitUntilExit()
        if linkProcess.terminationStatus != 0 { return nil }
        try FileManager.default.removeItem(atPath: moduleName + ".o")

        let executeProcess = Process()
        executeProcess.launchPath = moduleName + ".out"
        if stdoutPipe != nil { executeProcess.standardOutput = stdoutPipe }
        executeProcess.launch()
        executeProcess.waitUntilExit()
        try FileManager.default.removeItem(atPath: moduleName + ".out")

        return executeProcess.terminationStatus
    }

    private func determineModuleName(for inputFiles: [String]) -> String {
        if inputFiles.count == 1 { return inputFiles[0] }
        let commonPathPrefix = inputFiles.reduce(inputFiles[0]) { $0.commonPrefix(with: $1) }
        let parentDirectoryName = commonPathPrefix.components(separatedBy: "/").dropLast().last!
        return parentDirectoryName
    }

    private func determineCompilationOrder(of inputFiles: [String]) -> [String] {
        guard let mainFileIndex = inputFiles.index(where: {
            $0.components(separatedBy: "/").last!.caseInsensitiveCompare("main.gaia") == .orderedSame
        }) else {
            return inputFiles
        }
        var orderedInputFiles = inputFiles
        orderedInputFiles.append(orderedInputFiles.remove(at: mainFileIndex)) // Move main.gaia last.
        return orderedInputFiles
    }

    /// Returns whether the compilation completed successfully.
    public func compile(inputFiles: [String]) -> Bool {
        if inputFiles.isEmpty {
            outputStream.write("error: no input files\n")
            exit(1)
        }
        return compile(files: determineCompilationOrder(of: inputFiles))
    }

    /// Returns whether the compilation completed successfully.
    private func compile(files inputFileNames: [String]) -> Bool {
        initModule(moduleName: determineModuleName(for: inputFileNames))
        initFunctionPassManager(for: module)
        compileCoreLibrary()
        for inputFileName in inputFileNames {
            if !compileFile(inputFileName) { return false }
        }
        emitModule(as: LLVMObjectFile, toPath: determineModuleName(for: inputFileNames))
        return true
    }

    /// Returns whether the compilation completed successfully.
    fileprivate func compileFile(_ inputFileName: String) -> Bool {
        guard let inputFile = try? SourceFile(atPath: inputFileName) else {
            outputStream.write("error reading input file \(inputFileName), aborting\n")
            return false
        }

        do {
            let parser = Parser(readingFrom: inputFile)
            while try handleNextToken(parser: parser) { }
            return true
        } catch {
            emitError(error, file: inputFileName)
            return false
        }
    }

    /// Returns whether there are still tokens to be handled.
    public func handleNextToken(parser: Parser) throws -> Bool {
        switch try parser.nextToken() {
            case .eof: return false
            case .newline: break
            case .keyword(.function): try handleFunctionDefinition(parser: parser)
            case .keyword(.extern): try handleExternFunctionDeclaration(parser: parser)
            default: try handleToplevelExpression(parser: parser)
        }
        return true
    }

    private func emitError(_ error: Error, file: String) {
        let currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        guard #available(macOS 10.11, *) else {
            fatalError("This program requires macOS 10.11 or greater.")
        }
        let relativeFileURL = URL(fileURLWithPath: file, relativeTo: currentDirectoryURL)

        if let sourceCodeError = error as? SourceCodeError {
            if let location = sourceCodeError.location, let fileContents = try? String(contentsOfFile: file) {
                outputStream.write("\(relativeFileURL.relativePath):\(location): error: \(sourceCodeError)\n")
                let line = fileContents.components(separatedBy: .newlines)[location.line - 1]
                outputStream.write("\(line)\n\(String(repeating: " ", count: location.column - 1))^\n")
            } else {
                outputStream.write("\(relativeFileURL.relativePath): error: \(sourceCodeError)\n")
            }
        } else {
            outputStream.write("\(error)")
        }
    }

    private func emitModule(as codeGenFileType: LLVMCodeGenFileType, toPath outputFilePath: String) {
        irGenerator.appendImplicitZeroReturnToMainFunction()

        if emitInLLVMFormat {
            if codeGenFileType == LLVMObjectFile {
                if (outputFilePath + ".bc").withCString({ LLVMWriteBitcodeToFile(irGenerator.module.ref, $0) }) != 0 {
                    fatalError("LLVMWriteBitcodeToFile failed")
                }
            }
            if codeGenFileType == LLVMAssemblyFile {
                fatalError("LLVM IR emit to file not implemented")
            }
        } else {
            try! targetMachine.emitToFile(module, atPath: outputFilePath + ".o", fileType: codeGenFileType)
        }
    }

    public func handleFunctionDefinition(parser: Parser) throws {
        let function = try parser.parseFunctionDefinition()
        _ = try function.acceptVisitor(typeChecker)
        irGenerator.registerFunctionDefinition(function)
    }

    public func handleExternFunctionDeclaration(parser: Parser) throws {
        let prototype = try parser.parseExternFunctionDeclaration()
        _ = try prototype.acceptVisitor(typeChecker)
        irGenerator.registerExternFunctionDeclaration(prototype)
    }

    open func handleToplevelExpression(parser: Parser) throws {
        // Add top-level statements into main function.
        let statement = try parser.parseStatement()
        _ = try statement.acceptVisitor(typeChecker)
        try irGenerator.appendToMainFunction(statement)
    }

    public func initModule(moduleName: String) {
        module = LLVM.Module(name: moduleName)
        module.dataLayout = targetMachine.dataLayout.string
        module.target = LLVM.defaultTargetTriple
        irGenerator.module = module
    }

    public func initFunctionPassManager(for module: LLVM.Module) {
        let functionPassManager = LLVM.FunctionPassManager(for: module)
        // Promote allocas to registers.
        functionPassManager.addPromoteMemoryToRegisterPass()
        // Do simple "peephole" and bit-twiddling optimizations.
        functionPassManager.addInstructionCombiningPass()
        // Reassociate expressions.
        functionPassManager.addReassociatePass()
        // Eliminate common subexpressions.
        functionPassManager.addGVNPass()
        // Simplify the control flow graph (deleting unreachable blocks, etc.).
        functionPassManager.addCFGSimplificationPass()
        functionPassManager.initialize()
        irGenerator.functionPassManager = functionPassManager
    }

    public func compileCoreLibrary() {
        let onError = { print("Core library compilation failed.") }
        guard let coreLibraryFiles = try? findCoreLibraryFiles() else { return onError() }
        for file in coreLibraryFiles {
            if !compileFile(file) { return onError() }
        }
    }
}

private func findCoreLibraryFiles() throws -> [String] {
    guard let gaiaHome = ProcessInfo.processInfo.environment["GAIA_HOME"] else {
        fatalError("GAIA_HOME not defined")
    }
    let coreLibPath = gaiaHome + "/Core/"
    return try FileManager.default.contentsOfDirectory(atPath: coreLibPath).map { coreLibPath + $0 }
}

public final class Stdout: TextOutputStream {
    public init() { }

    public func write(_ string: String) {
        print(string, terminator: "")
    }
}
