public protocol Statement: ASTNode {
    var sourceLocation: SourceLocation { get }
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
