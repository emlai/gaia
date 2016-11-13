public final class Function: ASTNode {
    public let prototype: FunctionPrototype
    public let body: [Expression]

    public init(prototype: FunctionPrototype, body: [Expression]) {
        self.prototype = prototype
        self.body = body
    }

    public func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult {
        return try visitor.visit(function: self)
    }
}

public final class FunctionPrototype: ASTNode {
    public let name: String
    public let parameters: [Parameter]

    public init(name: String, parameters: [Parameter]) {
        self.name = name
        self.parameters = parameters
    }

    public func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult {
        return try visitor.visit(prototype: self)
    }
}

public final class Parameter {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}
