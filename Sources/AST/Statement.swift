public protocol ASTStatement: ASTNode { }

public class ASTIfStatement: ASTStatement {
    public let condition: ASTExpression
    public let then: [ASTStatement]
    public let `else`: [ASTStatement]
    public let sourceLocation: SourceLocation

    public init(condition: ASTExpression, then: [ASTStatement], else: [ASTStatement], at sourceLocation: SourceLocation) {
        self.condition = condition
        self.then = then
        self.else = `else`
        self.sourceLocation = sourceLocation
    }

    public func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult {
        return try visitor.visit(ifStatement: self)
    }
}

public class ASTReturnStatement: ASTStatement {
    public let value: ASTExpression?
    public let sourceLocation: SourceLocation

    public init(value: ASTExpression, at sourceLocation: SourceLocation) {
        self.value = value
        self.sourceLocation = sourceLocation
    }

    public func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult {
        return try visitor.visit(returnStatement: self)
    }
}

public class ASTVariableDefinition: ASTStatement {
    public let name: String
    public let value: ASTExpression
    public let sourceLocation: SourceLocation

    public init(name: String, value: ASTExpression, at sourceLocation: SourceLocation) {
        self.name = name
        self.value = value
        self.sourceLocation = sourceLocation
    }

    public func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult {
        return try visitor.visit(variableDefinition: self)
    }
}
