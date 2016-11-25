import LLVM_C
import LLVM
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
    private var globalModule: LLVM.Module!
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
        irGenerator = IRGenerator()
        variables = [:]
        initModuleAndFunctionPassManager()
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
        let ir = try function.acceptVisitor(irGenerator) as! LLVM.Function

        // JIT the anonymous function.
        let result = LLVMRunFunction(executionEngine, ir.ref, 0, nil)!
        defer { LLVMDisposeGenericValue(result) }

        outputStream.write(evaluate(result, type: ir.functionType.returnType))
        outputStream.write("\n")

        initModuleAndFunctionPassManager()
    }

    private func handleVariableDefinition(_ variableDefinition: VariableDefinition) {
        variables[variableDefinition.name] = variableDefinition
    }

    private func evaluate(_ result: LLVMGenericValueRef, type: LLVM.TypeType) -> String {
        switch type {
            case LLVM.VoidType(): return ""
            case LLVM.IntType.int1(): return LLVMGenericValueToInt(result, 0) != 0 ? "true" : "false"
            case LLVM.IntType.int64(): return String(Int64(bitPattern: LLVMGenericValueToInt(result, 1)))
            case LLVM.RealType.double(): return String(LLVMGenericValueToFloat(type.ref, result))
            default:
                if type.kind == LLVMPointerTypeKind
                && LLVMGetElementType(type.ref) == LLVM.IntType.int8().ref {
                    return "\"\(String(cString: LLVMGenericValueToPointer(result).assumingMemoryBound(to: Int8.self)))\""
                }
                return "unknown type '\(type.string)'"
        }
    }

    private func initModuleAndFunctionPassManager() {
        globalModule = LLVM.Module(name: "gaiajit")

        var errorMessage: UnsafeMutablePointer<CChar>? = nil
        if LLVMCreateExecutionEngineForModule(&executionEngine, globalModule.ref, &errorMessage) != 0 {
            defer { LLVMDisposeMessage(errorMessage) }
            fatalError(String(cString: errorMessage!))
        }
        LLVMSetModuleDataLayout(globalModule.ref, LLVMGetExecutionEngineTargetData(executionEngine))

        let functionPassManager = LLVMCreateFunctionPassManagerForModule(globalModule.ref)
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
