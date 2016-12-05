public protocol Statement: MIRNode { }

public class IfStatement: Statement {
    public let condition: Expression
    public let then: [Statement]
    public let `else`: [Statement]

    public init(condition: Expression, then: [Statement], else: [Statement]) {
        self.condition = condition
        self.then = then
        self.else = `else`
    }

    public func acceptVisitor<T: MIRVisitor>(_ visitor: T) -> T.VisitResult {
        return visitor.visit(ifStatement: self)
    }
}

public class ReturnStatement: Statement {
    public let value: Expression?

    public init(value: Expression?) {
        self.value = value
    }

    public func acceptVisitor<T: MIRVisitor>(_ visitor: T) -> T.VisitResult {
        return visitor.visit(returnStatement: self)
    }
}

public class VariableDefinition: Statement {
    public let name: String
    public let value: Expression
    public var type: Type { return value.type }

    public init(name: String, value: Expression) {
        self.name = name
        self.value = value
    }

    public func acceptVisitor<T: MIRVisitor>(_ visitor: T) -> T.VisitResult {
        return visitor.visit(variableDefinition: self)
    }
}
