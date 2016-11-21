public final class Function: ASTNode {
    public let prototype: FunctionPrototype
    public let body: [Statement]

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

    public init(name: String, parameters: [Parameter], returnType: String?) {
        self.name = name
        self.parameters = parameters
        self.returnType = returnType
    }

    public func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult {
        return try visitor.visit(prototype: self)
    }
}

public final class BinaryOperatorPrototype: FunctionPrototype {
    public let `operator`: BinaryOperator

    public init(operator: BinaryOperator, lhs: Parameter, rhs: Parameter, returnType: String?) {
        self.operator = `operator`
        super.init(name: self.operator.rawValue, parameters: [lhs, rhs], returnType: returnType)
    }
}

public final class UnaryOperatorPrototype: FunctionPrototype {
    public let `operator`: UnaryOperator

    public init(operator: UnaryOperator, operand: Parameter, returnType: String?) {
        self.operator = `operator`
        super.init(name: self.operator.rawValue, parameters: [operand], returnType: returnType)
    }
}

public final class Parameter {
    public let name: String
    public let type: String?

    public init(name: String, type: String?) {
        self.name = name
        self.type = type
    }
}
