import LLVM_C
import LLVM
import Parse
import AST
import MIR
import Driver

public final class REPL: Driver {
    private var infoOutputStream: TextOutputStream
    private let parser: Parser
    private var variables: [String: ASTVariableDefinition]
    private var executionEngine: LLVM.ExecutionEngine!

    public init(inputStream: TextInputStream = Stdin(), outputStream: TextOutputStream = Stdout(),
                infoOutputStream: TextOutputStream = Stdout()) {
        self.infoOutputStream = infoOutputStream
        parser = Parser(readingFrom: inputStream)
        variables = [:]
        super.init(outputStream: outputStream, allowRedefinitions: true)
        initModuleAndFunctionPassManager()
        compileCoreLibrary()
    }

    public func run() {
        var count = 0
        while true {
            infoOutputStream.write("\(count)> ")
            do {
                if try !handleNextToken(parser: parser) { return }
            } catch {
                outputStream.write("\(error)\n")
                try? parser.skipLine()
            }
            count += 1
        }
    }

    public override func handleToplevelExpression(parser: Parser) throws {
        // Evaluate a top-level statement into an anonymous function.
        let astStatement = try parser.parseStatement()

        // Except if it's a variable definition.
        if let variableDefinition = astStatement as? ASTVariableDefinition {
            handleVariableDefinition(variableDefinition)
            return
        }

        var body = try variables.map { try $0.value.acceptVisitor(typeChecker) as! Statement }
        let statement = try astStatement.acceptVisitor(typeChecker) as! Statement
        let returnType = (statement as? Expression)?.type ?? .void
        let prototype = FunctionPrototype(name: "__anon_expr", parameters: [],
                                          returnType: returnType, body: nil)
        if let expression = statement as? Expression {
            body.append(ReturnStatement(value: expression))
        } else {
            body.append(statement)
        }
        let function = Function(prototype: prototype, body: body, type: returnType)
        prototype.body = function
        irGenerator.arguments = []
        let ir = function.acceptVisitor(irGenerator) as! LLVM.Function

        let result = executionEngine.runFunction(ir, args: [])

        outputStream.write(evaluate(result, type: ir.functionType.returnType))
        outputStream.write("\n")

        initModuleAndFunctionPassManager()
    }

    private func handleVariableDefinition(_ variableDefinition: ASTVariableDefinition) {
        variables[variableDefinition.name] = variableDefinition
    }

    private func evaluate(_ result: LLVM.GenericValue, type: LLVM.TypeType) -> String {
        switch type {
            case LLVM.VoidType(): return ""
            case LLVM.IntType.int1(): return result.asInt(signed: false) != 0 ? "true" : "false"
            case LLVM.IntType.int64(): return String(Int64(bitPattern: result.asInt(signed: true)))
            case LLVM.RealType.double(): return String(result.asFloat(type: type))
            default:
                if type.kind == LLVMPointerTypeKind
                && LLVMGetElementType(type.ref) == LLVM.IntType.int8().ref {
                    return "\"\(String(cString: result.asPointer!.assumingMemoryBound(to: Int8.self)))\""
                }
                return "unknown type '\(type.string)'"
        }
    }

    private func initModuleAndFunctionPassManager() {
        module = LLVM.Module(name: "gaiajit")
        executionEngine = try! LLVM.ExecutionEngine(for: module)
        module.dataLayout = executionEngine.targetData.string
        irGenerator.module = module
        initFunctionPassManager(for: module)
    }
}
