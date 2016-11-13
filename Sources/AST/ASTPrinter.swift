public final class Stdout: TextOutputStream {
    public init() { }

    public func write(_ string: String) {
        print(string, terminator: "")
    }
}

public final class ASTPrinter: ASTVisitor {
    private var outputStream: TextOutputStream

    public init(printingTo outputStream: TextOutputStream) {
        self.outputStream = outputStream
    }

    public func visit(variable: Variable) throws {
        outputStream.write(variable.name)
    }

    public func visit(unaryOperation: UnaryOperation) throws {
        outputStream.write(unaryOperation.operator.rawValue)
        try unaryOperation.operand.acceptVisitor(self)
    }

    public func visit(binaryOperation: BinaryOperation) throws {
        outputStream.write("(")
        try binaryOperation.leftOperand.acceptVisitor(self)
        outputStream.write(" \(binaryOperation.operator.rawValue) ")
        try binaryOperation.rightOperand.acceptVisitor(self)
        outputStream.write(")")
    }

    public func visit(functionCall: FunctionCall) throws {
        outputStream.write(functionCall.functionName)
        outputStream.write("(")
        for argument in functionCall.arguments.dropLast() {
            try argument.acceptVisitor(self)
            outputStream.write(", ")
        }
        try functionCall.arguments.last?.acceptVisitor(self)
        outputStream.write(")")
    }

    public func visit(integerLiteral: IntegerLiteral) throws {
        outputStream.write(String(integerLiteral.value))
    }

    public func visit(floatingPointLiteral: FloatingPointLiteral) throws {
        outputStream.write(String(floatingPointLiteral.value))
    }

    public func visit(booleanLiteral: BooleanLiteral) throws {
        outputStream.write(String(booleanLiteral.value))
    }

    public func visit(if: If) throws {
        outputStream.write("if ")
        try `if`.condition.acceptVisitor(self)
        outputStream.write(" then ")
        try `if`.then.forEach { try $0.acceptVisitor(self) }
        outputStream.write(" else ")
        try `if`.else.forEach { try $0.acceptVisitor(self) }
    }

    public func visit(function: Function) throws {
        try function.prototype.acceptVisitor(self)
        try function.body.forEach { try $0.acceptVisitor(self) }
    }

    public func visit(prototype functionPrototype: FunctionPrototype) throws {
        // TODO
    }
}
