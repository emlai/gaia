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
    case variable(name: String)
    case unary(operator: UnaryOperator, operand: Expression)
    case binary(operator: BinaryOperator, leftOperand: Expression, rightOperand: Expression)
    case functionCall(functionName: String, arguments: [Expression])
    case `if`(condition: Expression, then: Expression, else: Expression)

    public func acceptVisitor(_ visitor: ASTVisitor) throws {
        switch self {
            case .integerLiteral(let value):
                try visitor.visitIntegerLiteralExpression(value: value)
            case .floatingPointLiteral(let value):
                try visitor.visitFloatingPointLiteralExpression(value: value)
            case .booleanLiteral(let value):
                try visitor.visitBooleanLiteralExpression(value: value)
            case .variable(let name):
                try visitor.visitVariableExpression(name: name)
            case .unary(let op, let operand):
                try visitor.visitUnaryExpression(operator: op, operand: operand)
            case .binary(let op, let lhs, let rhs):
                try visitor.visitBinaryExpression(operator: op, lhs: lhs, rhs: rhs)
            case .functionCall(let functionName, let arguments):
                try visitor.visitFunctionCallExpression(functionName: functionName, arguments: arguments)
            case .if(let condition, let then, let `else`):
                try visitor.visitIfExpression(condition: condition, then: then, else: `else`)
        }
    }
}
