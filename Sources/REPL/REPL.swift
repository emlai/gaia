import LLVM_C.ExecutionEngine
import LLVM_C.Transforms.Scalar
import LLVM_C.Types
import Parse
import AST
import IRGen
import JIT

public final class REPL {
    private var outputStream: TextOutputStream
    private var infoOutputStream: TextOutputStream
    private let parser: Parser
    private let astPrinter: ASTPrinter
    private let irGenerator: IRGenerator
    private var globalModule: LLVMModuleRef?
    private var executionEngine: LLVMExecutionEngineRef?
    private let jit: GaiaJITRef

    public init(inputStream: TextInputStream = Stdin(), outputStream: TextOutputStream = Stdout(),
                infoOutputStream: TextOutputStream = Stdout()) {
        LLVMInitializeNativeTarget()
        LLVMInitializeNativeAsmPrinter()
        LLVMInitializeNativeAsmParser()

        jit = GaiaCreateJIT()

        self.outputStream = outputStream
        self.infoOutputStream = infoOutputStream
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
            infoOutputStream.write("\(count)> ")
            do {
                switch parser.nextToken() {
                    case .eof: return
                    case .newline: break
                    case .keyword(.func): try handleFunctionDefinition()
                    case .keyword(.extern): try handleExternFunctionDeclaration()
                    default: try handleToplevelExpression()
                }
            } catch IRGenError.unknownIdentifier(_, let message) {
                outputStream.write("\(message)\n")
            } catch IRGenError.invalidType(let message) {
                outputStream.write("\(message)\n")
            } catch {
                _ = parser.nextToken() // Skip token for error recovery.
            }
            count += 1
        }
    }

    private func handleFunctionDefinition() throws {
        let function = try parser.parseFunctionDefinition()
        irGenerator.registerFunctionDefinition(function)
    }

    private func handleExternFunctionDeclaration() throws {
        let prototype = try parser.parseExternFunctionDeclaration()
        irGenerator.registerExternFunctionDeclaration(prototype)
    }

    private func handleToplevelExpression() throws {
        // Evaluate a top-level expression into an anonymous function.
        let expression = try parser.parseExpression()
        let prototype = FunctionPrototype(name: "__anon_expr", parameters: [])
        let function = Function(prototype: prototype, body: [expression])
        irGenerator.registerFunctionDefinition(function)
        irGenerator.argumentTypes = []
        let ir = try function.acceptVisitor(irGenerator)

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

    typealias VoidFunction = @convention(c) () -> Void
    typealias BoolFunction = @convention(c) () -> CBool
    typealias Int64Function = @convention(c) () -> Int64
    typealias DoubleFunction = @convention(c) () -> Double

    private func evaluate(_ function: UnsafeRawPointer, type: LLVMTypeRef) -> String {
        switch type {
            case LLVMVoidType(): unsafeBitCast(function, to: VoidFunction.self)(); return ""
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
