public enum UnaryOperator: String {
    case not = "!"
    case plus = "+"
    case minus = "-"
}

public enum BinaryOperator: String {
    case assignment = "="
    case equals = "=="
    case notEquals = "!="
    case lessThan = "<"
    case lessThanOrEqual = "<="
    case greaterThan = ">"
    case greaterThanOrEqual = ">="
    case plus = "+"
    case minus = "-"
    case multiplication = "*"
    case division = "/"

    public var precedence: Int {
        switch self {
            case .assignment: return 1
            case .equals, .notEquals: return 2
            case .lessThan, .lessThanOrEqual, .greaterThan, .greaterThanOrEqual: return 3
            case .plus, .minus: return 4
            case .multiplication, .division: return 5
        }
    }
}

public indirect enum Expression: ASTNode {
    case integerLiteral(value: Int64)
    case floatingPointLiteral(value: Float64)
    case booleanLiteral(value: Bool)
    case variable(location: SourceLocation, name: String)
    case unary(operator: UnaryOperator, operand: Expression)
    case binary(operator: BinaryOperator, leftOperand: Expression, rightOperand: Expression)
    case functionCall(location: SourceLocation, functionName: String, arguments: [Expression])
    case `if`(condition: Expression, then: Expression, else: Expression)

    public func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult {
        switch self {
            case .integerLiteral(let value):
                return try visitor.visitIntegerLiteralExpression(value: value)
            case .floatingPointLiteral(let value):
                return try visitor.visitFloatingPointLiteralExpression(value: value)
            case .booleanLiteral(let value):
                return try visitor.visitBooleanLiteralExpression(value: value)
            case .variable(let location, let name):
                return try visitor.visitVariableExpression(location: location, name: name)
            case .unary(let op, let operand):
                return try visitor.visitUnaryExpression(operator: op, operand: operand)
            case .binary(let op, let lhs, let rhs):
                return try visitor.visitBinaryExpression(operator: op, lhs: lhs, rhs: rhs)
            case .functionCall(let location, let functionName, let arguments):
                return try visitor.visitFunctionCallExpression(location: location,
                                                               functionName: functionName,
                                                               arguments: arguments)
            case .if(let condition, let then, let `else`):
                return try visitor.visitIfExpression(condition: condition, then: then, else: `else`)
        }
    }
}
