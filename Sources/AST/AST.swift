protocol ASTNode {
    func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult
}

public protocol ASTVisitor {
    associatedtype VisitResult
    func visitVariableExpression(name: String) throws -> VisitResult
    func visitUnaryExpression(operator: UnaryOperator, operand: Expression) throws -> VisitResult
    func visitBinaryExpression(operator: BinaryOperator, lhs: Expression, rhs: Expression) throws -> VisitResult
    func visitFunctionCallExpression(functionName: String, arguments: [Expression]) throws -> VisitResult
    func visitIntegerLiteralExpression(value: Int64) throws -> VisitResult
    func visitFloatingPointLiteralExpression(value: Float64) throws -> VisitResult
    func visitBooleanLiteralExpression(value: Bool) throws -> VisitResult
    func visitIfExpression(condition: Expression, then: Expression, else: Expression) throws -> VisitResult
    func visitFunction(_: Function) throws -> VisitResult
    func visitFunctionPrototype(_: FunctionPrototype) throws -> VisitResult
}
