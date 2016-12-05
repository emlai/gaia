public protocol ASTNode {
    func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult
    var sourceLocation: SourceLocation { get }
}

public protocol ASTVisitor {
    associatedtype VisitResult
    func visit(variable: ASTVariable) throws -> VisitResult
    func visit(functionCall: ASTFunctionCall) throws -> VisitResult
    func visit(integerLiteral: ASTIntegerLiteral) throws -> VisitResult
    func visit(floatingPointLiteral: ASTFloatingPointLiteral) throws -> VisitResult
    func visit(booleanLiteral: ASTBooleanLiteral) throws -> VisitResult
    func visit(stringLiteral: ASTStringLiteral) throws -> VisitResult
    func visit(nullLiteral: ASTNullLiteral) throws -> VisitResult
    func visit(ifExpression: ASTIfExpression) throws -> VisitResult
    func visit(ifStatement: ASTIfStatement) throws -> VisitResult
    func visit(function: ASTFunction) throws -> VisitResult
    func visit(prototype: ASTPrototype) throws -> VisitResult
    func visit(returnStatement: ASTReturnStatement) throws -> VisitResult
    func visit(variableDefinition: ASTVariableDefinition) throws -> VisitResult
}

public struct SourceLocation: CustomStringConvertible {
    /// A textual representation of this instance.
    public var description: String {
        return "\(line):\(column)"
    }

    public private(set) var line: Int
    public private(set) var column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }

    public mutating func advanceToNextLine() {
        line += 1
        column = 0
    }

    public mutating func advanceToNextColumn() {
        column += 1
    }
}

public protocol SourceCodeError: Error, CustomStringConvertible {
    var location: SourceLocation? { get }
}
