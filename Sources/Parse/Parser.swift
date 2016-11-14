import Foundation
import AST

public enum ParseError: Error {
    case unexpectedToken(String)
}

public final class Parser {
    private let lexer: Lexer
    private var token: Token! /// The token currently being processed.
    private var tokenSourceLocation: SourceLocation!

    public init(readingFrom inputStream: TextInputStream = Stdin()) {
        lexer = Lexer(readFrom: inputStream)
        token = nil
        tokenSourceLocation = nil
    }

    public func nextToken() -> Token {
        let (tokenSourceLocation, token) = lexer.lex()
        self.tokenSourceLocation = tokenSourceLocation
        self.token = token
        return token
    }

    public func skipLine() {
        while token != .newline {
            _ = nextToken()
        }
    }

    private func expectToken(oneOf expected: [Token], _ message: String? = nil) throws {
        if !expected.contains(token) {
            throw ParseError.unexpectedToken(message ?? "expected one of \(expected)")
        }
    }

    private func expectToken(_ expected: Token, _ message: String? = nil) throws {
        if token != expected {
            throw ParseError.unexpectedToken(message ?? "expected \(expected)")
        }
    }

    func parseFunctionPrototype() throws -> FunctionPrototype {
        _ = nextToken() // consume 'func'

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
        let prototype = try parseFunctionPrototype()
        var body = [Expression]()

        if token == .newline {
            // Multi-line function
            while nextToken() != .keyword(.end) {
                body.append(try parseExpression())
            }
        } else {
            // One-line function
            body.append(try parseExpression())
        }

        return Function(prototype: prototype, body: body)
    }

    public func parseExternFunctionDeclaration() throws -> FunctionPrototype {
        _ = nextToken() // consume 'extern'
        return try parseFunctionPrototype()
    }

    private func parseIntegerLiteral() -> Expression {
        guard case .integerLiteral(let value)? = token else { fatalError() }
        let e = IntegerLiteral(value: value, at: tokenSourceLocation)
        _ = nextToken() // consume the literal
        return e
    }

    private func parseBooleanLiteral() -> Expression {
        let e: Expression
        switch token {
            case .keyword(.true)?: e = BooleanLiteral(value: true, at: tokenSourceLocation)
            case .keyword(.false)?: e = BooleanLiteral(value: false, at: tokenSourceLocation)
            default: preconditionFailure()
        }
        _ = nextToken() // consume the literal
        return e
    }

    private func parseFloatingPointLiteral() -> Expression {
        guard case .floatingPointLiteral(let value)? = token else { fatalError() }
        let e = FloatingPointLiteral(value: value, at: tokenSourceLocation)
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

        let identifierSourceLocation = tokenSourceLocation!

        if nextToken() != .leftParenthesis {
            // It's a variable.
            return Variable(name: identifier, at: identifierSourceLocation)
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
        return FunctionCall(functionName: identifier, arguments: arguments, at: identifierSourceLocation)
    }

    private func parsePrimaryExpression() throws -> Expression {
        switch token {
            case .identifier?: return try parseIdentifier()
            case .integerLiteral?: return parseIntegerLiteral()
            case .floatingPointLiteral?: return parseFloatingPointLiteral()
            case .keyword(.true)?, .keyword(.false)?: return parseBooleanLiteral()
            case .keyword(.if)?: return try parseIf()
            case .leftParenthesis?: return try parseParenthesizedExpression()
            default: throw ParseError.unexpectedToken("unexpected \(token!)")
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
        let operatorLocation = tokenSourceLocation!
        _ = nextToken()
        return UnaryOperation(operator: unaryOperator, operand: try parseUnaryExpression(),
                              at: operatorLocation)
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
            let operatorLocation = tokenSourceLocation!
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
            lhs = BinaryOperation(operator: binaryOperator, leftOperand: lhs,
                                  rightOperand: rhs, at: operatorLocation)
        }
    }

    private func parseIf() throws -> Expression {
        let ifLocation = tokenSourceLocation!
        _ = nextToken() // consume 'if'
        let condition = try parseExpression()
        try expectToken(oneOf: [.keyword(.then), .newline],
                        "expected `then` or newline after `if` condition")
        var thenBranch = [Expression]()
        var elseBranch = [Expression]()

        if token == .newline {
            // Multi-line if
            while nextToken() != .keyword(.else) {
                thenBranch.append(try parseExpression())
                try expectToken(.newline)
            }
            _ = nextToken() // consume 'else'
            try expectToken(.newline)
            while nextToken() != .keyword(.end) {
                elseBranch.append(try parseExpression())
                try expectToken(.newline)
            }
            _ = nextToken() // consume 'end'
            try expectToken(.newline)
        } else {
            // One-line if
            _ = nextToken() // consume 'then'
            thenBranch.append(try parseExpression())
            try expectToken(.keyword(.else))
            _ = nextToken() // consume 'else'
            elseBranch.append(try parseExpression())
        }

        return If(condition: condition, then: thenBranch, else: elseBranch, at: ifLocation)
    }
}
