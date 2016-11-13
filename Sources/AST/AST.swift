public protocol ASTNode {
    func acceptVisitor<T: ASTVisitor>(_ visitor: T) throws -> T.VisitResult
}

public protocol ASTVisitor {
    associatedtype VisitResult
    func visit(variable: Variable) throws -> VisitResult
    func visit(unaryOperation: UnaryOperation) throws -> VisitResult
    func visit(binaryOperation: BinaryOperation) throws -> VisitResult
    func visit(functionCall: FunctionCall) throws -> VisitResult
    func visit(integerLiteral: IntegerLiteral) throws -> VisitResult
    func visit(floatingPointLiteral: FloatingPointLiteral) throws -> VisitResult
    func visit(booleanLiteral: BooleanLiteral) throws -> VisitResult
    func visit(if: If) throws -> VisitResult
    func visit(function: Function) throws -> VisitResult
    func visit(prototype: FunctionPrototype) throws -> VisitResult
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
