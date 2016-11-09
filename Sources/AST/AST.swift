protocol ASTNode {
    func acceptVisitor(_ visitor: ASTVisitor) throws
}

public protocol ASTVisitor {
    func visitVariableExpression(name: String) throws
    func visitUnaryExpression(operator: UnaryOperator, operand: Expression) throws
    func visitBinaryExpression(operator: BinaryOperator, lhs: Expression, rhs: Expression) throws
    func visitFunctionCallExpression(functionName: String, arguments: [Expression]) throws
    func visitIntegerLiteralExpression(value: Int64) throws
    func visitFloatingPointLiteralExpression(value: Float64) throws
    func visitBooleanLiteralExpression(value: Bool) throws
    func visitIfExpression(condition: Expression, then: Expression, else: Expression) throws
    func visitFunction(_: Function) throws
    func visitFunctionPrototype(_: FunctionPrototype) throws
}
