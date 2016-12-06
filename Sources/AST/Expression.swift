public enum UnaryOperator: String {
    case not = "!"
    case plus = "+"
    case minus = "-"
    case addressOf = "&"
}

public enum BinaryOperator: String {
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
            case .equals, .notEquals: return 2
            case .lessThan, .lessThanOrEqual, .greaterThan, .greaterThanOrEqual: return 3
            case .plus, .minus: return 4
            case .multiplication, .division: return 5
        }
    }

    public var isOverloadable: Bool {
        return [.equals, .lessThan, .plus, .minus, .multiplication, .division].contains(self)
    }
}

public protocol ASTExpression: ASTStatement { }

public class ASTIntegerLiteral: ASTExpression {
    public let value: Int64
    public let sourceLocation: SourceLocation

    public init(value: Int64, at sourceLocation: SourceLocation) {
        self.value = value
        self.sourceLocation = sourceLocation
    }

    public func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult {
        return try visitor.visit(integerLiteral: self)
    }
}

public class ASTFloatingPointLiteral: ASTExpression {
    public let value: Float64
    public let sourceLocation: SourceLocation

    public init(value: Float64, at sourceLocation: SourceLocation) {
        self.value = value
        self.sourceLocation = sourceLocation
    }

    public func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult {
        return try visitor.visit(floatingPointLiteral: self)
    }
}

public class ASTBooleanLiteral: ASTExpression {
    public let value: Bool
    public let sourceLocation: SourceLocation

    public init(value: Bool, at sourceLocation: SourceLocation) {
        self.value = value
        self.sourceLocation = sourceLocation
    }

    public func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult {
        return try visitor.visit(booleanLiteral: self)
    }
}

public class ASTStringLiteral: ASTExpression {
    public let value: String
    public let sourceLocation: SourceLocation

    public init(value: String, at sourceLocation: SourceLocation) {
        self.value = value
        self.sourceLocation = sourceLocation
    }

    public func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult {
        return try visitor.visit(stringLiteral: self)
    }
}

public class ASTNullLiteral: ASTExpression {
    public let sourceLocation: SourceLocation

    public init(at sourceLocation: SourceLocation) {
        self.sourceLocation = sourceLocation
    }

    public func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult {
        return try visitor.visit(nullLiteral: self)
    }
}

public class ASTVariable: ASTExpression {
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

public class ASTFunctionCall: ASTExpression {
    public let functionName: String
    public let arguments: [ASTExpression]
    public let sourceLocation: SourceLocation
    public var isUnaryOperation: Bool { return UnaryOperator(rawValue: functionName) != nil && arguments.count == 1 }
    public var isBinaryOperation: Bool { return BinaryOperator(rawValue: functionName) != nil && arguments.count == 2 }

    public init(functionName: String, arguments: [ASTExpression], at sourceLocation: SourceLocation) {
        self.functionName = functionName
        self.arguments = arguments
        self.sourceLocation = sourceLocation
    }

    public func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult {
        return try visitor.visit(functionCall: self)
    }
}

public class ASTIfExpression: ASTExpression {
    public let condition: ASTExpression
    public let then: ASTExpression
    public let `else`: ASTExpression
    public let sourceLocation: SourceLocation

    public init(condition: ASTExpression, then: ASTExpression, else: ASTExpression, at sourceLocation: SourceLocation) {
        self.condition = condition
        self.then = then
        self.else = `else`
        self.sourceLocation = sourceLocation
    }

    public func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult {
        return try visitor.visit(ifExpression: self)
    }
}
