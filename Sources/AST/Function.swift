public final class ASTFunction: ASTNode {
    public let prototype: ASTPrototype
    public let body: [ASTStatement]
    public var sourceLocation: SourceLocation { return prototype.sourceLocation }

    public init(prototype: ASTPrototype, body: [ASTStatement]) {
        self.prototype = prototype
        self.body = body
    }

    public func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult {
        return try visitor.visit(function: self)
    }
}

public class ASTPrototype: ASTNode {
    public let name: String
    public let parameters: [ASTParameter]
    public let returnType: String?
    public let isExtern: Bool
    public let sourceLocation: SourceLocation

    public init(name: String, parameters: [ASTParameter], returnType: String?, isExtern: Bool,
                at sourceLocation: SourceLocation) {
        self.name = name
        self.parameters = parameters
        self.returnType = returnType
        self.isExtern = isExtern
        self.sourceLocation = sourceLocation
    }

    public func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult {
        return try visitor.visit(prototype: self)
    }
}

public final class ASTBinaryOperatorPrototype: ASTPrototype {
    public let `operator`: BinaryOperator

    public init(operator: BinaryOperator, lhs: ASTParameter, rhs: ASTParameter,
                returnType: String?, at sourceLocation: SourceLocation) {
        self.operator = `operator`
        super.init(name: self.operator.rawValue, parameters: [lhs, rhs],
                   returnType: returnType, isExtern: false, at: sourceLocation)
    }
}

public final class ASTUnaryOperatorPrototype: ASTPrototype {
    public let `operator`: UnaryOperator

    public init(operator: UnaryOperator, operand: ASTParameter,
                returnType: String?, at sourceLocation: SourceLocation) {
        self.operator = `operator`
        super.init(name: self.operator.rawValue, parameters: [operand],
                   returnType: returnType, isExtern: false, at: sourceLocation)
    }
}

public final class ASTParameter {
    public let name: String
    public let type: String?
    public let sourceLocation: SourceLocation

    public init(name: String, type: String?, at sourceLocation: SourceLocation) {
        self.name = name
        self.type = type
        self.sourceLocation = sourceLocation
    }
}
