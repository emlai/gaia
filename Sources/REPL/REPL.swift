import LLVM_C.ExecutionEngine
import LLVM_C.Transforms.Scalar
import LLVM_C.Types
import Parse
import AST
import IRGen
import JIT

public final class REPL {
    private var outputStream: TextOutputStream
    private let parser: Parser
    private let astPrinter: ASTPrinter
    private let irGenerator: IRGenerator
    private var globalModule: LLVMModuleRef?
    private var executionEngine: LLVMExecutionEngineRef?
    private let jit: GaiaJITRef

    public init(inputStream: TextInputStream = Stdin(), outputStream: TextOutputStream = Stdout()) {
        LLVMInitializeNativeTarget();
        LLVMInitializeNativeAsmPrinter();
        LLVMInitializeNativeAsmParser();

        jit = GaiaCreateJIT()

        self.outputStream = outputStream
        parser = Parser(readingFrom: inputStream)
        astPrinter = ASTPrinter(printingTo: outputStream)
        irGenerator = IRGenerator(context: LLVMGetGlobalContext())
        initModuleAndFunctionPassManager()
    }

    deinit {
        GaiaDisposeJIT(jit)
    }

    public func run() {
        var count = 0
        while true {
            print("\(count)> ", terminator: "")
            do {
                switch parser.nextToken() {
                    case .eof: return
                    case .newline: break
                    case .keyword(.func): try handleFunctionDefinition()
                    default: try handleToplevelExpression()
                }
            } catch IRGenError.unknownIdentifier(let message) {
                outputStream.write("\(message)\n")
            } catch {
                _ = parser.nextToken() // Skip token for error recovery.
            }
            count += 1
        }
    }

    private func handleFunctionDefinition() throws {
        let function = try parser.parseFunctionDefinition()

        try function.acceptVisitor(irGenerator)
        let ir = irGenerator.result!

        LLVMDumpValue(ir)

        GaiaJITAddModule(jit, &globalModule)
        initModuleAndFunctionPassManager()
    }

    private func handleToplevelExpression() throws {
        // Evaluate a top-level expression into an anonymous function.
        let function = try parser.parseToplevelExpression()

        try function.acceptVisitor(irGenerator)
        let ir = irGenerator.result!

        // Get the type of the expression.
        let type = LLVMGetReturnType(LLVMGetElementType(LLVMTypeOf(ir)))!

        // JIT the module containing the anonymous expression,
        // keeping a handle so we can free it later.
        let moduleHandle = GaiaJITAddModule(jit, &globalModule)
        defer { GaiaJITDisposeModuleHandle(moduleHandle) }
        initModuleAndFunctionPassManager()

        guard let symbolAddress = GaiaJITFindSymbolAddress(jit, "__anon_expr") else {
            fatalError("function not found")
        }

        outputStream.write(evaluate(symbolAddress, type: type))
        outputStream.write("\n")

        // Delete the anonymous expression module from the JIT.
        GaiaJITRemoveModule(jit, moduleHandle)
    }

    typealias BoolFunction = @convention(c) () -> CBool
    typealias Int64Function = @convention(c) () -> Int64
    typealias DoubleFunction = @convention(c) () -> Double

    private func evaluate(_ function: UnsafeRawPointer, type: LLVMTypeRef) -> String {
        switch type {
            case LLVMInt1Type(): return String(unsafeBitCast(function, to: BoolFunction.self)())
            case LLVMInt64Type(): return String(unsafeBitCast(function, to: Int64Function.self)())
            case LLVMDoubleType(): return String(unsafeBitCast(function, to: DoubleFunction.self)())
            default:
                let typeName = LLVMPrintTypeToString(type)
                defer { LLVMDisposeMessage(typeName) }
                return "unknown type '\(String(cString: typeName!))'"
        }
    }

    private func initModuleAndFunctionPassManager() {
        globalModule = LLVMModuleCreateWithName("gaiajit")
        LLVMSetModuleDataLayout(globalModule, LLVMCreateTargetDataLayout(GaiaGetJITTargetMachine(jit)))

        let functionPassManager = LLVMCreateFunctionPassManagerForModule(globalModule)
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

        irGenerator.module = globalModule
        irGenerator.functionPassManager = functionPassManager
    }
}
