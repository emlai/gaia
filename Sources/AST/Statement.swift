public protocol Statement: ASTNode { }

public class IfStatement: Statement {
    public let condition: Expression
    public let then: [Statement]
    public let `else`: [Statement]
    public let sourceLocation: SourceLocation

    public init(condition: Expression, then: [Statement], else: [Statement], at sourceLocation: SourceLocation) {
        self.condition = condition
        self.then = then
        self.else = `else`
        self.sourceLocation = sourceLocation
    }

    public func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult {
        return try visitor.visit(ifStatement: self)
    }
}

public class ReturnStatement: Statement {
    public let value: Expression?
    public let sourceLocation: SourceLocation

    public init(value: Expression, at sourceLocation: SourceLocation) {
        self.value = value
        self.sourceLocation = sourceLocation
    }

    public func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult {
        return try visitor.visit(returnStatement: self)
    }
}

public class VariableDefinition: Statement {
    public let name: String
    public let value: Expression
    public let sourceLocation: SourceLocation

    public init(name: String, value: Expression, at sourceLocation: SourceLocation) {
        self.name = name
        self.value = value
        self.sourceLocation = sourceLocation
    }

    public func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult {
        return try visitor.visit(variableDefinition: self)
    }
}
