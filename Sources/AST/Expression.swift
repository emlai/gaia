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

public protocol Expression: ASTNode { }

public class IntegerLiteral: Expression {
    public let value: Int64

    public init(value: Int64) {
        self.value = value
    }

    public func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult {
        return try visitor.visit(integerLiteral: self)
    }
}

public class FloatingPointLiteral: Expression {
    public let value: Float64

    public init(value: Float64) {
        self.value = value
    }

    public func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult {
        return try visitor.visit(floatingPointLiteral: self)
    }
}

public class BooleanLiteral: Expression {
    public let value: Bool

    public init(value: Bool) {
        self.value = value
    }

    public func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult {
        return try visitor.visit(booleanLiteral: self)
    }
}

public class Variable: Expression {
    public let name: String
    public let sourceLocation: SourceLocation

    public init(name: String, at sourceLocation: SourceLocation) {
        self.name = name
        self.sourceLocation = sourceLocation
    }

    public func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult {
        return try visitor.visit(variable: self)
    }
}

public class UnaryOperation: Expression {
    public let `operator`: UnaryOperator
    public let operand: Expression

    public init(operator: UnaryOperator, operand: Expression) {
        self.operator = `operator`
        self.operand = operand
    }

    public func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult {
        return try visitor.visit(unaryOperation: self)
    }
}

public class BinaryOperation: Expression {
    public let `operator`: BinaryOperator
    public let leftOperand: Expression
    public let rightOperand: Expression

    public init(operator: BinaryOperator, leftOperand: Expression, rightOperand: Expression) {
        self.operator = `operator`
        self.leftOperand = leftOperand
        self.rightOperand = rightOperand
    }

    public func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult {
        return try visitor.visit(binaryOperation: self)
    }
}

public class FunctionCall: Expression {
    public let functionName: String
    public let arguments: [Expression]
    public let sourceLocation: SourceLocation

    public init(functionName: String, arguments: [Expression], at sourceLocation: SourceLocation) {
        self.functionName = functionName
        self.arguments = arguments
        self.sourceLocation = sourceLocation
    }

    public func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult {
        return try visitor.visit(functionCall: self)
    }
}

public class If: Expression {
    public let condition: Expression
    public let then: [Expression]
    public let `else`: [Expression]

    public init(condition: Expression, then: [Expression], else: [Expression]) {
        self.condition = condition
        self.then = then
        self.else = `else`
    }

    public func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult {
        return try visitor.visit(if: self)
    }
}
