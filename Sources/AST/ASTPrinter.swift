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

    public func visitVariableExpression(name: String) throws {
        outputStream.write(name)
    }

    public func visitUnaryExpression(operator: UnaryOperator, operand: Expression) throws {
        outputStream.write(`operator`.rawValue)
        try operand.acceptVisitor(self)
    }

    public func visitBinaryExpression(operator: BinaryOperator, lhs: Expression, rhs: Expression) throws {
        outputStream.write("(")
        try lhs.acceptVisitor(self)
        outputStream.write(" \(`operator`.rawValue) ")
        try rhs.acceptVisitor(self)
        outputStream.write(")")
    }

    public func visitFunctionCallExpression(functionName: String, arguments: [Expression]) throws {
        outputStream.write(functionName)
        outputStream.write("(")
        for argument in arguments.dropLast() {
            try argument.acceptVisitor(self)
            outputStream.write(", ")
        }
        try arguments.last?.acceptVisitor(self)
        outputStream.write(")")
    }

    public func visitIntegerLiteralExpression(value: Int64) throws {
        outputStream.write(String(value))
    }

    public func visitBooleanLiteralExpression(value: Bool) throws {
        outputStream.write(String(value))
    }

    public func visitIfExpression(condition: Expression, then: Expression, else: Expression) throws {
        outputStream.write("if ")
        try condition.acceptVisitor(self)
        outputStream.write(" then ")
        try then.acceptVisitor(self)
        outputStream.write(" else ")
        try `else`.acceptVisitor(self)
    }

    public func visitFunction(_ function: Function) throws {
        try function.prototype.acceptVisitor(self)
        try function.body.acceptVisitor(self)
    }

    public func visitFunctionPrototype(_: FunctionPrototype) throws {
        // TODO
    }
}
