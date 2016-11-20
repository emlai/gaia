import LLVM_C
import Parse
import AST
import IRGen
import Driver

public final class REPL {
    private var outputStream: TextOutputStream
    private var infoOutputStream: TextOutputStream
    private let parser: Parser
    private let astPrinter: ASTPrinter
    private let irGenerator: IRGenerator
    private var variables: [String: VariableDefinition]
    private var globalModule: LLVMModuleRef?
    private var executionEngine: LLVMExecutionEngineRef?

    public init(inputStream: TextInputStream = Stdin(), outputStream: TextOutputStream = Stdout(),
                infoOutputStream: TextOutputStream = Stdout()) {
        LLVMInitializeNativeTarget()
        LLVMInitializeNativeAsmPrinter()
        LLVMInitializeNativeAsmParser()

        self.outputStream = outputStream
        self.infoOutputStream = infoOutputStream
        parser = Parser(readingFrom: inputStream)
        astPrinter = ASTPrinter(printingTo: outputStream)
        irGenerator = IRGenerator(context: LLVMGetGlobalContext())
        variables = [:]
        initModuleAndFunctionPassManager()
    }

    deinit {
        LLVMDisposeExecutionEngine(executionEngine)
    }

    public func run() {
        var count = 0
        while true {
            infoOutputStream.write("\(count)> ")
            do {
                switch try parser.nextToken() {
                    case .eof: return
                    case .newline: break
                    case .keyword(.func): try handleFunctionDefinition()
                    case .keyword(.extern): try handleExternFunctionDeclaration()
                    default: try handleToplevelExpression()
                }
            } catch {
                outputStream.write("\(error)\n")
                try? parser.skipLine()
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
        // Evaluate a top-level statement into an anonymous function.
        let statement = try parser.parseStatement()

        // Except if it's a variable definition.
        if let variableDefinition = statement as? VariableDefinition {
            handleVariableDefinition(variableDefinition)
            return
        }

        let prototype = FunctionPrototype(name: "__anon_expr", parameters: [], returnType: nil)
        var body = variables.map { $0.value as Statement }
        if let expression = statement as? Expression {
            body.append(ReturnStatement(value: expression, at: SourceLocation(line: -1, column: -1)))
        } else {
            body.append(statement)
        }
        let function = Function(prototype: prototype, body: body)
        irGenerator.registerFunctionDefinition(function)
        irGenerator.arguments = []
        let ir = try function.acceptVisitor(irGenerator)

        // Get the type of the expression.
        let type = LLVMGetReturnType(LLVMGetElementType(LLVMTypeOf(ir)))!

        // JIT the anonymous function.
        let result = LLVMRunFunction(executionEngine, ir, 0, nil)!
        initModuleAndFunctionPassManager()

        outputStream.write(evaluate(result, type: type))
        outputStream.write("\n")
    }

    private func handleVariableDefinition(_ variableDefinition: VariableDefinition) {
        variables[variableDefinition.name] = variableDefinition
    }

    private func evaluate(_ result: LLVMGenericValueRef, type: LLVMTypeRef) -> String {
        switch type {
            case LLVMVoidType(): return ""
            case LLVMInt1Type(): return LLVMGenericValueToInt(result, 0) != 0 ? "true" : "false"
            case LLVMInt64Type(): return String(Int64(bitPattern: LLVMGenericValueToInt(result, 1)))
            case LLVMDoubleType(): return String(LLVMGenericValueToFloat(type, result))
            default:
                if LLVMGetTypeKind(type) == LLVMPointerTypeKind
                && LLVMGetElementType(type) == LLVMInt8Type() {
                    return "\"\(String(cString: LLVMGenericValueToPointer(result).assumingMemoryBound(to: Int8.self)))\""
                }

                let typeName = LLVMPrintTypeToString(type)
                defer { LLVMDisposeMessage(typeName) }
                return "unknown type '\(String(cString: typeName!))'"
        }
    }

    private func initModuleAndFunctionPassManager() {
        globalModule = LLVMModuleCreateWithName("gaiajit")

        var errorMessage: UnsafeMutablePointer<CChar>? = nil
        if LLVMCreateExecutionEngineForModule(&executionEngine, globalModule, &errorMessage) != 0 {
            defer { LLVMDisposeMessage(errorMessage) }
            fatalError(String(cString: errorMessage!))
        }
        LLVMSetModuleDataLayout(globalModule, LLVMGetExecutionEngineTargetData(executionEngine))

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
        compileCoreLibrary(with: irGenerator)
    }
}
