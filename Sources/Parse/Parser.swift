import Foundation
import AST

public enum ParseError: SourceCodeError {
    case unexpectedToken(String)
    case unterminatedStringLiteral(location: SourceLocation)

    public var location: SourceLocation? {
        switch self {
            case .unexpectedToken: return nil
            case .unterminatedStringLiteral(let location): return location
        }
    }

    public var description: String {
        switch self {
            case .unexpectedToken(let message): return message
            case .unterminatedStringLiteral: return "unterminated string literal"
        }
    }
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

    public func nextToken() throws -> Token {
        let (tokenSourceLocation, token) = try lexer.lex()
        self.tokenSourceLocation = tokenSourceLocation
        self.token = token
        return token
    }

    public func skipLine() throws {
        while token != .newline {
            _ = try nextToken()
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
        _ = try nextToken() // consume 'func'

        guard case .identifier(let functionName)? = token else {
            throw ParseError.unexpectedToken("expected function name in prototype")
        }

        _ = try nextToken()
        try expectToken(.leftParenthesis, "expected '(' in prototype")

        var parameters = [Parameter]()
        while case .identifier(let parameterName) = try nextToken() {
            switch try nextToken() {
                case .colon:
                    switch try nextToken() {
                        case .identifier(let typeName):
                            parameters.append(Parameter(name: parameterName, type: typeName))
                            _ = try nextToken() // consume parameter type
                        default:
                            throw ParseError.unexpectedToken("expected parameter type after `:`")
                    }
                default:
                    parameters.append(Parameter(name: parameterName, type: nil))
            }
            if token != .comma { break }
        }

        try expectToken(.rightParenthesis, "expected ',' or ')' in parameter list")

        let returnType: String?
        if try nextToken() == .arrow {
            switch try nextToken() {
                case .identifier(let typeName): returnType = typeName; _ = try nextToken()
                default: throw ParseError.unexpectedToken("expected return type after `->`")
            }
        } else {
            returnType = nil
        }

        return FunctionPrototype(name: functionName, parameters: parameters, returnType: returnType)
    }

    public func parseFunctionDefinition() throws -> Function {
        let prototype = try parseFunctionPrototype()
        var body = [Statement]()

        if token == .newline {
            // Multi-line function
            while try nextToken() != .keyword(.end) {
                body.append(try parseStatement())
            }
        } else {
            // One-line function
            body.append(try parseStatement())
        }

        return Function(prototype: prototype, body: body)
    }

    public func parseExternFunctionDeclaration() throws -> FunctionPrototype {
        _ = try nextToken() // consume 'extern'
        return try parseFunctionPrototype()
    }

    private func parseIntegerLiteral() throws -> Expression {
        guard case .integerLiteral(let value)? = token else { fatalError() }
        let e = IntegerLiteral(value: value, at: tokenSourceLocation)
        _ = try nextToken() // consume the literal
        return e
    }

    private func parseBooleanLiteral() throws -> Expression {
        let e: Expression
        switch token {
            case .keyword(.true)?: e = BooleanLiteral(value: true, at: tokenSourceLocation)
            case .keyword(.false)?: e = BooleanLiteral(value: false, at: tokenSourceLocation)
            default: preconditionFailure()
        }
        _ = try nextToken() // consume the literal
        return e
    }

    private func parseFloatingPointLiteral() throws -> Expression {
        guard case .floatingPointLiteral(let value)? = token else { fatalError() }
        let e = FloatingPointLiteral(value: value, at: tokenSourceLocation)
        _ = try nextToken() // consume the literal
        return e
    }

    private func parseStringLiteral() throws -> Expression {
        guard case .stringLiteral(let value)? = token else { fatalError() }
        let e = StringLiteral(value: value, at: tokenSourceLocation)
        _ = try nextToken() // consume the literal
        return e
    }

    private func parseParenthesizedExpression() throws -> Expression {
        _ = try nextToken() // consume '('
        let e = try parseExpression()
        try expectToken(.rightParenthesis)
        _ = try nextToken() // consume ')'
        return e
    }

    private func parseIdentifier() throws -> Expression {
        guard case .identifier(let identifier)? = token else {
            fatalError()
        }

        let identifierSourceLocation = tokenSourceLocation!

        if try nextToken() != .leftParenthesis {
            // It's a variable.
            return Variable(name: identifier, at: identifierSourceLocation)
        }

        // It's a function call.
        var arguments = [Expression]()

        if try nextToken() != .rightParenthesis {
            while true {
                let argument = try parseExpression()
                arguments.append(argument)
                if token == .rightParenthesis { break }
                try expectToken(.comma, "expected ')' or ',' in argument list")
                _ = try nextToken()
            }
        }
        _ = try nextToken() // consume ')'
        return FunctionCall(functionName: identifier, arguments: arguments, at: identifierSourceLocation)
    }

    private func parsePrimaryExpression() throws -> Expression {
        switch token {
            case .identifier?: return try parseIdentifier()
            case .integerLiteral?: return try parseIntegerLiteral()
            case .floatingPointLiteral?: return try parseFloatingPointLiteral()
            case .stringLiteral?: return try parseStringLiteral()
            case .keyword(.true)?, .keyword(.false)?: return try parseBooleanLiteral()
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
        _ = try nextToken()
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
            _ = try nextToken()

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
        _ = try nextToken() // consume 'if'
        let condition = try parseExpression()
        try expectToken(oneOf: [.keyword(.then), .newline],
                        "expected `then` or newline after `if` condition")
        var thenBranch = [Statement]()
        var elseBranch = [Statement]()

        if token == .newline {
            // Multi-line if
            while try nextToken() != .keyword(.else) {
                thenBranch.append(try parseStatement())
                try expectToken(.newline)
            }
            _ = try nextToken() // consume 'else'
            try expectToken(.newline)
            while try nextToken() != .keyword(.end) {
                elseBranch.append(try parseStatement())
                try expectToken(.newline)
            }
            _ = try nextToken() // consume 'end'
            try expectToken(.newline)
        } else {
            // One-line if
            _ = try nextToken() // consume 'then'
            thenBranch.append(try parseExpression())
            try expectToken(.keyword(.else))
            _ = try nextToken() // consume 'else'
            elseBranch.append(try parseExpression())
        }

        return If(condition: condition, then: thenBranch, else: elseBranch, at: ifLocation)
    }

    public func parseStatement() throws -> Statement {
        switch token {
            case .keyword(.return)?: return try parseReturnStatement()
            default: return try parseExpression()
        }
    }

    private func parseReturnStatement() throws -> ReturnStatement {
        let returnLocation = tokenSourceLocation!
        _ = try nextToken() // consume 'return'
        return ReturnStatement(value: try parseExpression(), at: returnLocation)
    }
}
