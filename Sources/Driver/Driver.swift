import Foundation
import LLVM_C
import Parse
import AST
import IRGen

#if os(Linux)
typealias Process = Task
#endif

public final class Driver {
    private var outputStream: TextOutputStream
    private var parser: Parser?
    private let irGenerator: IRGenerator
    private let targetTriple: UnsafeMutablePointer<CChar>
    private var targetMachine: LLVMTargetMachineRef?
    private var module: LLVMModuleRef?

    public init(outputStream: TextOutputStream = Stdout(), using irGenerator: IRGenerator? = nil) {
        LLVMInitializeNativeTarget()
        LLVMInitializeNativeAsmPrinter()
        LLVMInitializeNativeAsmParser()

        self.outputStream = outputStream
        self.irGenerator = irGenerator ?? IRGenerator(context: LLVMGetGlobalContext())

        targetTriple = LLVMGetDefaultTargetTriple()
        defer { LLVMDisposeMessage(targetTriple) }

        var target: LLVMTargetRef? = nil
        var errorMessage: UnsafeMutablePointer<CChar>? = nil
        if LLVMGetTargetFromTriple(targetTriple, &target, &errorMessage) != 0 {
            self.outputStream.write("\(String(cString: errorMessage!))\n")
            exit(1)
        }

        targetMachine = LLVMCreateTargetMachine(target, targetTriple, "generic", "",
                                                LLVMCodeGenLevelNone, LLVMRelocDefault,
                                                LLVMCodeModelDefault)
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
        initModuleAndFunctionPassManager(moduleName: determineModuleName(for: inputFileNames))
        compileCoreLibrary(with: irGenerator)
        for inputFileName in inputFileNames {
            if !compileFile(inputFileName) { return false }
        }
        emitModule(as: LLVMObjectFile, toPath: determineModuleName(for: inputFileNames) + ".o")
        return true
    }

    /// Returns whether the compilation completed successfully.
    fileprivate func compileFile(_ inputFileName: String) -> Bool {
        guard let inputFile = try? SourceFile(atPath: inputFileName) else {
            outputStream.write("error reading input file \(inputFileName), aborting\n")
            return false
        }
        parser = Parser(readingFrom: inputFile)

        while true {
            do {
                switch try parser!.nextToken() {
                    case .eof: return true
                    case .newline: break
                    case .keyword(.func): try handleFunctionDefinition()
                    case .keyword(.extern): try handleExternFunctionDeclaration()
                    default: try handleToplevelExpression()
                }
            } catch {
                emitError(error, file: inputFileName)
                return false
            }
        }
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

        var errorMessage: UnsafeMutablePointer<CChar>? = nil
        if LLVMTargetMachineEmitToFile(targetMachine, module,
                                       UnsafeMutablePointer<CChar>(mutating: outputFilePath),
                                       codeGenFileType, &errorMessage) != 0 {
            outputStream.write("\(String(cString: errorMessage!))\n")
            exit(1)
        }
        LLVMDisposeMessage(errorMessage)
    }

    private func handleFunctionDefinition() throws {
        let function = try parser!.parseFunctionDefinition()
        irGenerator.registerFunctionDefinition(function)
    }

    private func handleExternFunctionDeclaration() throws {
        let prototype = try parser!.parseExternFunctionDeclaration()
        irGenerator.registerExternFunctionDeclaration(prototype)
    }

    private func handleToplevelExpression() throws {
        // Add top-level statements into main function.
        let statement = try parser!.parseStatement()
        try irGenerator.appendToMainFunction(statement)
    }

    private func initModuleAndFunctionPassManager(moduleName: String) {
        module = LLVMModuleCreateWithName(moduleName)
        LLVMSetModuleDataLayout(module, LLVMCreateTargetDataLayout(targetMachine))
        LLVMSetTarget(module, targetTriple)

        let functionPassManager = LLVMCreateFunctionPassManagerForModule(module)
        // Promote allocas to registers.
        LLVMAddPromoteMemoryToRegisterPass(functionPassManager)
        // Do simple "peephole" and bit-twiddling optimizations.
        LLVMAddInstructionCombiningPass(functionPassManager)
        // Reassociate expressions.
        LLVMAddReassociatePass(functionPassManager)
        // Eliminate common subexpressions.
        LLVMAddGVNPass(functionPassManager)
        // Simplify the control flow graph (deleting unreachable blocks, etc.).
        LLVMAddCFGSimplificationPass(functionPassManager)
        LLVMInitializeFunctionPassManager(functionPassManager)

        irGenerator.module = module
        irGenerator.functionPassManager = functionPassManager
    }
}

private func findCoreLibraryFiles() throws -> [String] {
    guard let gaiaHome = ProcessInfo.processInfo.environment["GAIA_HOME"] else {
        fatalError("GAIA_HOME not defined")
    }
    let coreLibPath = gaiaHome + "/Core/"
    return try FileManager.default.contentsOfDirectory(atPath: coreLibPath).map { coreLibPath + $0 }
}

public func compileCoreLibrary(with irGenerator: IRGenerator) {
    let driver = Driver(using: irGenerator)
    let onError = { print("Core library compilation failed.") }
    guard let coreLibraryFiles = try? findCoreLibraryFiles() else { return onError() }
    for file in coreLibraryFiles {
        if !driver.compileFile(file) { return onError() }
    }
}
