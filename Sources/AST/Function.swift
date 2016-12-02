public final class Function: ASTNode {
    public let prototype: FunctionPrototype
    public let body: [Statement]
    public var sourceLocation: SourceLocation { return prototype.sourceLocation }

    public init(prototype: FunctionPrototype, body: [Statement]) {
        self.prototype = prototype
        self.body = body
    }

    public func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult {
        return try visitor.visit(function: self)
    }
}

public class FunctionPrototype: ASTNode {
    public let name: String
    public let parameters: [Parameter]
    public let returnType: String?
    public let sourceLocation: SourceLocation

    public init(name: String, parameters: [Parameter], returnType: String?,
                at sourceLocation: SourceLocation) {
        self.name = name
        self.parameters = parameters
        self.returnType = returnType
        self.sourceLocation = sourceLocation
    }

    public func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult {
        return try visitor.visit(prototype: self)
    }
}

public final class BinaryOperatorPrototype: FunctionPrototype {
    public let `operator`: BinaryOperator

    public init(operator: BinaryOperator, lhs: Parameter, rhs: Parameter,
                returnType: String?, at sourceLocation: SourceLocation) {
        self.operator = `operator`
        super.init(name: self.operator.rawValue, parameters: [lhs, rhs],
                   returnType: returnType, at: sourceLocation)
    }
}

public final class UnaryOperatorPrototype: FunctionPrototype {
    public let `operator`: UnaryOperator

    public init(operator: UnaryOperator, operand: Parameter,
                returnType: String?, at sourceLocation: SourceLocation) {
        self.operator = `operator`
        super.init(name: self.operator.rawValue, parameters: [operand],
                   returnType: returnType, at: sourceLocation)
    }
}

public final class Parameter {
    public let name: String
    public let type: String?
    public let sourceLocation: SourceLocation

    public init(name: String, type: String?, at sourceLocation: SourceLocation) {
        self.name = name
        self.type = type
        self.sourceLocation = sourceLocation
    }
}
