// MIR = mid-level intermediate representation

public protocol MIRNode {
    func acceptVisitor<T: MIRVisitor>(_ visitor: T) -> T.VisitResult
}

public protocol MIRVisitor {
    associatedtype VisitResult
    func visit(variable: Variable) -> VisitResult
    func visit(functionCall: FunctionCall) -> VisitResult
    func visit(integerLiteral: IntegerLiteral) -> VisitResult
    func visit(floatingPointLiteral: FloatingPointLiteral) -> VisitResult
    func visit(booleanLiteral: BooleanLiteral) -> VisitResult
    func visit(stringLiteral: StringLiteral) -> VisitResult
    func visit(nullLiteral: NullLiteral) -> VisitResult
    func visit(ifExpression: IfExpression) -> VisitResult
    func visit(ifStatement: IfStatement) -> VisitResult
    func visit(function: Function) -> VisitResult
    func visit(prototype: FunctionPrototype) -> VisitResult
    func visit(returnStatement: ReturnStatement) -> VisitResult
    func visit(variableDefinition: VariableDefinition) -> VisitResult
}
