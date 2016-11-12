import Foundation
import LLVM_C.ExecutionEngine
import LLVM_C.Transforms.Scalar
import Parse
import AST
import IRGen

public final class Driver {
    private var parser: Parser?
    private let irGenerator: IRGenerator
    private let targetTriple: UnsafeMutablePointer<CChar>
    private var targetMachine: LLVMTargetMachineRef?
    private var module: LLVMModuleRef?

    public init() {
        LLVMInitializeNativeTarget()
        LLVMInitializeNativeAsmPrinter()
        LLVMInitializeNativeAsmParser()

        irGenerator = IRGenerator(context: LLVMGetGlobalContext())

        targetTriple = LLVMGetDefaultTargetTriple()
        defer { LLVMDisposeMessage(targetTriple) }

        var target: LLVMTargetRef? = nil
        var errorMessage: UnsafeMutablePointer<CChar>? = nil
        if LLVMGetTargetFromTriple(targetTriple, &target, &errorMessage) != 0 {
            print(String(cString: errorMessage!))
            exit(1)
        }

        targetMachine = LLVMCreateTargetMachine(target, targetTriple, "generic", "",
                                                LLVMCodeGenLevelNone, LLVMRelocDefault,
                                                LLVMCodeModelDefault)
    }

    public func run(inputFiles: ArraySlice<String>) {
        if inputFiles.isEmpty {
            print("error: no input files")
            exit(1)
        }

        for inputFileName in inputFiles {
            compile(file: inputFileName)
        }
    }

    private func compile(file inputFileName: String) {
        print("Compiling \(inputFileName)... ", terminator: "")
        initModuleAndFunctionPassManager(moduleName: inputFileName)
        compileModule(inputFileName)
        emitModule(as: LLVMObjectFile, toPath: inputFileName + ".o")
        print("Done.")
    }

    private func compileModule(_ inputFileName: String) {
        guard let inputFile = try? SourceFile(atPath: inputFileName) else {
            print("error reading input file \(inputFileName), aborting")
            exit(1)
        }
        parser = Parser(readingFrom: inputFile)

        while true {
            do {
                switch parser!.nextToken() {
                    case .eof: return
                    case .newline: break
                    case .keyword(.func): try handleFunctionDefinition()
                    case .keyword(.extern): try handleExternFunctionDeclaration()
                    default: try handleToplevelExpression()
                }
            } catch IRGenError.unknownIdentifier(let message) {
                print(message)
                exit(1)
            } catch IRGenError.invalidType(let message) {
                print(message)
                exit(1)
            } catch {
                exit(1)
            }
        }
    }

    private func emitModule(as codeGenFileType: LLVMCodeGenFileType, toPath outputFilePath: String) {
        var errorMessage: UnsafeMutablePointer<CChar>? = nil
        if LLVMTargetMachineEmitToFile(targetMachine, module,
                                       UnsafeMutablePointer<CChar>(mutating: outputFilePath),
                                       codeGenFileType, &errorMessage) != 0 {
            print(String(cString: errorMessage!))
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
