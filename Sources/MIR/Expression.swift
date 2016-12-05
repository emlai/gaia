import enum AST.UnaryOperator
import enum AST.BinaryOperator

public protocol Expression: Statement {
    var type: Type { get }
}

public class Variable: Expression {
    public let name: String
    public let type: Type

    public init(_ name: String, _ type: Type) {
        self.name = name
        self.type = type
    }

    public func acceptVisitor<T: MIRVisitor>(_ visitor: T) -> T.VisitResult {
        return visitor.visit(variable: self)
    }
}

public class FunctionCall: Expression {
    public let target: FunctionPrototype
    public let arguments: [Expression]
    public let type: Type
    public var isUnaryOperation: Bool { return arguments.count == 1 && UnaryOperator(rawValue: target.name) != nil }
    public var isBinaryOperation: Bool { return arguments.count == 2 && BinaryOperator(rawValue: target.name) != nil }

    public init(target: FunctionPrototype, arguments: [Expression], type: Type) {
        self.target = target
        self.arguments = arguments
        self.type = type
    }

    public func acceptVisitor<T: MIRVisitor>(_ visitor: T) -> T.VisitResult {
        return visitor.visit(functionCall: self)
    }
}

public class IntegerLiteral: Expression {
    public let value: Int64
    public let type: Type = .int

    public init(value: Int64) {
        self.value = value
    }

    public func acceptVisitor<T: MIRVisitor>(_ visitor: T) -> T.VisitResult {
        return visitor.visit(integerLiteral: self)
    }
}

public class FloatingPointLiteral: Expression {
    public let value: Float64
    public let type: Type = .float

    public init(value: Float64) {
        self.value = value
    }

    public func acceptVisitor<T: MIRVisitor>(_ visitor: T) -> T.VisitResult {
        return visitor.visit(floatingPointLiteral: self)
    }
}

public class BooleanLiteral: Expression {
    public let value: Bool
    public let type: Type = .bool

    public init(value: Bool) {
        self.value = value
    }

    public func acceptVisitor<T: MIRVisitor>(_ visitor: T) -> T.VisitResult {
        return visitor.visit(booleanLiteral: self)
    }
}

public class StringLiteral: Expression {
    public let value: String
    public let type: Type = .string

    public init(value: String) {
        self.value = value
    }

    public func acceptVisitor<T: MIRVisitor>(_ visitor: T) -> T.VisitResult {
        return visitor.visit(stringLiteral: self)
    }
}

public class NullLiteral: Expression {
    public let type: Type = .typeOfNull

    public init() { }

    public func acceptVisitor<T: MIRVisitor>(_ visitor: T) -> T.VisitResult {
        return visitor.visit(nullLiteral: self)
    }
}

public class IfExpression: Expression {
    public let condition: Expression
    public let then: Expression
    public let `else`: Expression
    public let type: Type

    public init(condition: Expression, then: Expression, else: Expression, type: Type) {
        self.condition = condition
        self.then = then
        self.else = `else`
        self.type = type
    }

    public func acceptVisitor<T: MIRVisitor>(_ visitor: T) -> T.VisitResult {
        return visitor.visit(ifExpression: self)
    }
}
