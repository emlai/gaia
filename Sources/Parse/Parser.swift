import Foundation
import AST

enum ParseError: Error {
    case unexpectedToken(String)
}

public final class Parser {
    private let lexer: Lexer
    private var token: Token! /// The token currently being processed.

    public init(readingFrom inputStream: TextInputStream = Stdin()) {
        lexer = Lexer(readFrom: inputStream)
        token = nil
    }

    public func nextToken() -> Token {
        token = lexer.lex()
        return token
    }

    private func expectToken(oneOf expected: Token..., _ message: String? = nil) throws {
        if !expected.contains(token) {
            let message = message ?? "expected \(expected)"
            throw ParseError.unexpectedToken(message)
        }
    }

    private func expectToken(_ expected: Token, _ message: String? = nil) throws {
        try expectToken(oneOf: expected)
    }

    func parseFunctionPrototype() throws -> FunctionPrototype {
        guard case .identifier(let functionName)? = token else {
            throw ParseError.unexpectedToken("expected function name in prototype")
        }

        _ = nextToken()
        try expectToken(.leftParenthesis, "expected '(' in prototype")

        var parameters = [Parameter]()
        while case .identifier(let parameterName) = nextToken() {
            parameters.append(Parameter(name: parameterName))
            if nextToken() != .comma { break }
        }

        try expectToken(.rightParenthesis, "expected ',' or ')' in parameter list")
        _ = nextToken()

        return FunctionPrototype(name: functionName, parameters: parameters)
    }

    public func parseFunctionDefinition() throws -> Function {
        _ = nextToken()
        let prototype = try parseFunctionPrototype()
        let body = try parseExpression()
        return Function(prototype: prototype, body: body)
    }

    private func parseIntegerLiteral() -> Expression {
        guard case .integerLiteral(let value)? = token else { fatalError() }
        let e = Expression.integerLiteral(value: value)
        _ = nextToken() // consume the literal
        return e
    }

    private func parseBooleanLiteral() -> Expression {
        let e: Expression
        switch token {
            case .keyword(.true)?: e = .booleanLiteral(value: true)
            case .keyword(.false)?: e = .booleanLiteral(value: false)
            default: preconditionFailure()
        }
        _ = nextToken() // consume the literal
        return e
    }

    private func parseFloatingPointLiteral() -> Expression {
        guard case .floatingPointLiteral(let value)? = token else { fatalError() }
        let e = Expression.floatingPointLiteral(value: value)
        _ = nextToken() // consume the literal
        return e
    }

    private func parseParenthesizedExpression() throws -> Expression {
        _ = nextToken() // consume '('
        let e = try parseExpression()
        try expectToken(.rightParenthesis)
        _ = nextToken() // consume ')'
        return e
    }

    private func parseIdentifier() throws -> Expression {
        guard case .identifier(let identifier)? = token else {
            fatalError()
        }

        if nextToken() != .leftParenthesis {
            // It's a variable.
            return .variable(name: identifier)
        }

        // It's a function call.
        var arguments = [Expression]()

        if nextToken() != .rightParenthesis {
            while true {
                let argument = try parseExpression()
                arguments.append(argument)
                if token == .rightParenthesis { break }
                try expectToken(.comma, "expected ')' or ',' in argument list")
                _ = nextToken()
            }
        }
        _ = nextToken() // consume ')'
        return .functionCall(functionName: identifier, arguments: arguments)
    }

    private func parsePrimaryExpression() throws -> Expression {
        switch token {
            case .identifier?: return try parseIdentifier()
            case .integerLiteral?: return parseIntegerLiteral()
            case .floatingPointLiteral?: return parseFloatingPointLiteral()
            case .keyword(.true)?, .keyword(.false)?: return parseBooleanLiteral()
            case .keyword(.if)?: return try parseIf()
            case .leftParenthesis?: return try parseParenthesizedExpression()
            default: fatalError()
        }
    }

    public func parseExpression() throws -> Expression {
        return try parseBinOpRHS(precedence: 0, lhs: try parseUnaryExpression())
    }

    private func parseUnaryExpression() throws -> Expression {
        if token.isPrimary || token == .leftParenthesis || token == .comma {
            return try parsePrimaryExpression()
        }

        let unaryOperator: UnaryOperator
        switch token {
            case .not?: unaryOperator = .not
            case .plus?: unaryOperator = .plus
            case .minus?: unaryOperator = .minus
            default: throw ParseError.unexpectedToken("expected unary operator")
        }
        _ = nextToken()
        return .unary(operator: unaryOperator, operand: try parseUnaryExpression())
    }

    private func parseBinOpRHS(precedence: Int, lhs: Expression) throws -> Expression {
        var lhs = lhs

        while true {
            let tokenPrecedence = token.precedence

            // If this is a binary operator that binds at least as tightly as
            // the current binary operator, consume it, otherwise we're done.
            if tokenPrecedence < precedence { return lhs }

            // It's a binary operator.
            guard let binaryOperator = BinaryOperator(from: token) else {
                preconditionFailure("expected binary operator")
            }
            _ = nextToken()

            // Parse the unary expression after the binary operator.
            var rhs = try parseUnaryExpression()

            // If binaryOperator binds less tightly with rhs than the operator after
            // rhs, let the pending operator take rhs as its lhs.
            let nextTokenPrecedence = token.precedence
            if tokenPrecedence < nextTokenPrecedence {
                rhs = try parseBinOpRHS(precedence: tokenPrecedence + 1, lhs: rhs)
            }

            // Merge lhs and rhs.
            lhs = .binary(operator: binaryOperator, leftOperand: lhs, rightOperand: rhs)
        }
    }

    private func parseIf() throws -> Expression {
        _ = nextToken() // consume 'if'
        let condition = try parseExpression()
        try expectToken(oneOf: .keyword(.then), .newline)
        _ = nextToken() // consume 'then' or newline
        let thenBranch = try parseExpression()
        if token == .newline { _ = nextToken() } // consume optional newline
        try expectToken(.keyword(.else))
        _ = nextToken() // consume 'else'
        if token == .newline { _ = nextToken() } // consume optional newline
        let elseBranch = try parseExpression()
        return .if(condition: condition, then: thenBranch, else: elseBranch)
    }
}
