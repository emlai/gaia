/// An instantiated function.
public class Function: MIRNode {
    public let prototype: FunctionPrototype
    public let body: [Statement]
    public let type: Type

    public init(prototype: FunctionPrototype, body: [Statement], type: Type) {
        self.prototype = prototype
        self.body = body
        self.type = type
    }

    public func acceptVisitor<T: MIRVisitor>(_ visitor: T) -> T.VisitResult {
        return visitor.visit(function: self)
    }
}

/// A fully typed parameter of an instantiated function.
public struct Parameter {
    public let name: String
    public let type: Type

    public init(name: String, type: Type) {
        self.name = name
        self.type = type
    }
}

/// Prototype of an concrete instantiated function or extern function.
public class FunctionPrototype: MIRNode {
    public let name: String
    public let parameters: [Parameter]
    public let returnType: Type?
    public weak var body: Function?
    public var isExtern: Bool { return body == nil }

    public init(name: String, parameters: [Parameter], returnType: Type?, body: Function?) {
        self.name = name
        self.parameters = parameters
        self.returnType = returnType
        self.body = body
    }

    public func acceptVisitor<T: MIRVisitor>(_ visitor: T) -> T.VisitResult {
        return visitor.visit(prototype: self)
    }
}

public struct FunctionSignature: Hashable {
    let name: String
    let argumentTypes: [Type]

    public init(_ name: String, _ argumentTypes: [Type]) {
        self.name = name
        self.argumentTypes = argumentTypes
    }

    public static func ==(lhs: FunctionSignature, rhs: FunctionSignature) -> Bool {
        return lhs.name == rhs.name && lhs.argumentTypes == rhs.argumentTypes
    }

    public var hashValue: Int {
        return name.hashValue
    }
}

extension FunctionPrototype: Hashable {
    public static func ==(lhs: FunctionPrototype, rhs: FunctionPrototype) -> Bool {
        return lhs.name == rhs.name
            && lhs.parameters.map { $0.type } == rhs.parameters.map { $0.type }
            && lhs.returnType == rhs.returnType
    }

    public var hashValue: Int {
        return name.hashValue
    }
}
