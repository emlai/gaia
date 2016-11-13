import Foundation
import LLVM_C.ExecutionEngine
import LLVM_C.Transforms.Scalar
import Parse
import AST
import IRGen

public final class Driver {
    private var outputStream: TextOutputStream
    private var parser: Parser?
    private let irGenerator: IRGenerator
    private let targetTriple: UnsafeMutablePointer<CChar>
    private var targetMachine: LLVMTargetMachineRef?
    private var module: LLVMModuleRef?

    public init(outputStream: TextOutputStream = Stdout()) {
        LLVMInitializeNativeTarget()
        LLVMInitializeNativeAsmPrinter()
        LLVMInitializeNativeAsmParser()

        self.outputStream = outputStream
        irGenerator = IRGenerator(context: LLVMGetGlobalContext())

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

    /// Returns the exit status of the executed program on successful completion, or `nil` if
    /// the compiled program was not executed, e.g. because the compilation didn't succeed.
    public func compileAndExecute(inputFile: String, stdoutPipe: Pipe? = nil) throws -> Int32? {
        if !compile(file: inputFile) { return nil }

        let linkProcess = Process()
        linkProcess.launchPath = "/usr/bin/env"
        linkProcess.arguments = ["cc", inputFile + ".o", "-o", inputFile + ".out"]
        linkProcess.launch()
        linkProcess.waitUntilExit()
        if linkProcess.terminationStatus != 0 { return nil }
        try FileManager.default.removeItem(atPath: inputFile + ".o")

        let executeProcess = Process()
        executeProcess.launchPath = inputFile + ".out"
        if stdoutPipe != nil { executeProcess.standardOutput = stdoutPipe }
        executeProcess.launch()
        executeProcess.waitUntilExit()
        try FileManager.default.removeItem(atPath: inputFile + ".out")

        return executeProcess.terminationStatus
    }

    /// Returns whether the compilation completed successfully.
    public func compile(inputFiles: ArraySlice<String>) -> Bool {
        if inputFiles.isEmpty {
            outputStream.write("error: no input files\n")
            exit(1)
        }

        for inputFileName in inputFiles {
            if !compile(file: inputFileName) { return false }
        }
        return true
    }

    /// Returns whether the compilation completed successfully.
    private func compile(file inputFileName: String) -> Bool {
        initModuleAndFunctionPassManager(moduleName: inputFileName)
        if !compileModule(inputFileName) { return false }
        emitModule(as: LLVMObjectFile, toPath: inputFileName + ".o")
        return true
    }

    /// Returns whether the compilation completed successfully.
    private func compileModule(_ inputFileName: String) -> Bool {
        guard let inputFile = try? SourceFile(atPath: inputFileName) else {
            outputStream.write("error reading input file \(inputFileName), aborting\n")
            return false
        }
        parser = Parser(readingFrom: inputFile)

        while true {
            do {
                switch parser!.nextToken() {
                    case .eof: return true
                    case .newline: break
                    case .keyword(.func): try handleFunctionDefinition()
                    case .keyword(.extern): try handleExternFunctionDeclaration()
                    default: try handleToplevelExpression()
                }
            } catch IRGenError.unknownIdentifier(let location, let message) {
                emitError(message, file: inputFileName, location: location)
                return false
            } catch IRGenError.invalidType(let location, let message) {
                emitError(message, file: inputFileName, location: location)
                return false
            } catch {
                return false
            }
        }
    }

    private func emitError(_ message: String, file: String, location: SourceLocation) {
        let currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let relativeFileURL = URL(fileURLWithPath: file, relativeTo: currentDirectoryURL)
        outputStream.write("\(relativeFileURL.relativePath):\(location): error: \(message)\n")
        if let fileContents = try? String(contentsOfFile: file) {
            let line = fileContents.components(separatedBy: .newlines)[location.line - 1]
            outputStream.write("\(line)\n\(String(repeating: " ", count: location.column - 1))^\n")
        }
    }

    private func emitModule(as codeGenFileType: LLVMCodeGenFileType, toPath outputFilePath: String) {
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
        // Add top-level expressions into main function.
        let expression = try parser!.parseExpression()
        try irGenerator.appendToMainFunction(expression)
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
