protocol ASTNode {
    func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult
}

public protocol ASTVisitor {
    associatedtype VisitResult
    func visitVariableExpression(location: SourceLocation, name: String) throws -> VisitResult
    func visitUnaryExpression(operator: UnaryOperator, operand: Expression) throws -> VisitResult
    func visitBinaryExpression(operator: BinaryOperator, lhs: Expression, rhs: Expression) throws -> VisitResult
    func visitFunctionCallExpression(location: SourceLocation, functionName: String,
                                     arguments: [Expression]) throws -> VisitResult
    func visitIntegerLiteralExpression(value: Int64) throws -> VisitResult
    func visitFloatingPointLiteralExpression(value: Float64) throws -> VisitResult
    func visitBooleanLiteralExpression(value: Bool) throws -> VisitResult
    func visitIfExpression(condition: Expression, then: Expression, else: Expression) throws -> VisitResult
    func visitFunction(_: Function) throws -> VisitResult
    func visitFunctionPrototype(_: FunctionPrototype) throws -> VisitResult
}

public struct SourceLocation: CustomStringConvertible {
    /// A textual representation of this instance.
    public var description: String {
        return "\(line):\(column)"
    }

    public private(set) var line: Int
    public private(set) var column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = line
    }

    public mutating func advanceToNextLine() {
        line += 1
        column = 0
    }

    public mutating func advanceToNextColumn() {
        column += 1
    }
}
