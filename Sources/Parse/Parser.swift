import Foundation
import AST

public enum ParseError: SourceCodeError {
    case unexpectedToken(String)
    case unterminatedStringLiteral(location: SourceLocation)
    case invalidNumberOfParameters(String, location: SourceLocation)

    public var location: SourceLocation? {
        switch self {
            case .unexpectedToken: return nil
            case .unterminatedStringLiteral(let location),
                 .invalidNumberOfParameters(_, let location): return location
        }
    }

    public var description: String {
        switch self {
            case .unexpectedToken(let message),
                 .invalidNumberOfParameters(let message, _): return message
            case .unterminatedStringLiteral: return "unterminated string literal"
        }
    }
}

extension UnaryOperator {
    fileprivate init?(from binaryOperator: BinaryOperator) {
        switch binaryOperator {
            case .plus: self = .plus
            case .minus: self = .minus
            default: return nil
        }
    }
}

public final class Parser {
    private let lexer: Lexer
    private var tokens: [(SourceLocation, Token)]
    private var token: Token! { /// The token currently being processed.
        return tokens.last?.1
    }
    private var tokenSourceLocation: SourceLocation! {
        return tokens.last?.0
    }

    public init(readingFrom inputStream: TextInputStream = Stdin()) {
        lexer = Lexer(readFrom: inputStream)
        tokens = []
    }

    public func nextToken() throws -> Token {
        _ = tokens.popLast()
        if let top = tokens.last { return top.1 }
        tokens.append(try lexer.lex())
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

    /// Checks that the given token is the current token, then advances to the next token.
    private func skipExpectedToken(_ token: Token, _ message: String? = nil) throws {
        try expectToken(token, message)
        _ = try nextToken()
    }

    /// If the given token is the current token, advances to the next token. Otherwise does nothing.
    private func skipOptionalToken(_ token: Token) throws {
        if self.token == token { _ = try nextToken() }
    }

    func parseFunctionPrototype(isExtern: Bool = false) throws -> ASTPrototype {
        _ = try nextToken() // consume 'function'

        enum NameOrOperator {
            case name(String)
            case op(BinaryOperator) // Handles unary operators too (FIXME).
        }
        let nameLocation = tokenSourceLocation!
        let nameOrOperator: NameOrOperator
        switch token {
            case .identifier(let name)?: nameOrOperator = .name(name)
            case .binaryOperator(let op)?:
                if !op.isOverloadable {
                    throw ParseError.unexpectedToken("operator `\(op.rawValue)` is not overloadable")
                }
                nameOrOperator = .op(op)
            case .plus?: nameOrOperator = .op(.plus)
            case .minus?: nameOrOperator = .op(.minus)
            default: throw ParseError.unexpectedToken("expected function name in prototype")
        }

        _ = try nextToken()
        let parameters = try parseParameterList()

        let returnType: String?
        if try nextToken() == .arrow {
            switch try nextToken() {
                case .identifier(let typeName): returnType = typeName; _ = try nextToken()
                default: throw ParseError.unexpectedToken("expected return type after `->`")
            }
        } else {
            returnType = nil
        }

        switch nameOrOperator {
            case .name(let name):
                return ASTPrototype(name: name, parameters: parameters, returnType: returnType,
                                    isExtern: isExtern, at: nameLocation)
            case .op(let op):
                switch parameters.count {
                    case 2:
                        return ASTBinaryOperatorPrototype(operator: op, lhs: parameters[0], rhs: parameters[1],
                                                          returnType: returnType, at: nameLocation)
                    case 1:
                        return ASTUnaryOperatorPrototype(operator: UnaryOperator(from: op)!, operand: parameters[0],
                                                         returnType: returnType, at: nameLocation)
                    default: throw ParseError.invalidNumberOfParameters("invalid number of parameters " +
                                                                        "for operator `\(op.rawValue)`",
                                                                        location: nameLocation)
                }
        }
    }

    private func parseParameterList() throws -> [ASTParameter] {
        var parameters = [ASTParameter]()
        try expectToken(.leftParenthesis, "expected '(' in prototype")
        while try nextToken() != .rightParenthesis {
            parameters.append(try parseParameter())
            if token != .comma { break }
        }
        try expectToken(.rightParenthesis, "expected ',' or ')' in parameter list")
        return parameters
    }

    private func parseParameter() throws -> ASTParameter {
        guard case .identifier(let parameterName)? = token else { preconditionFailure() }
        let parameterNameLocation = tokenSourceLocation!

        switch try nextToken() {
            case .colon:
                switch try nextToken() {
                    case .identifier(let typeName):
                        _ = try nextToken() // consume parameter type
                        return ASTParameter(name: parameterName, type: typeName, at: parameterNameLocation)
                    default:
                        throw ParseError.unexpectedToken("expected parameter type after `:`")
                }
            case .comma, .rightParenthesis:
                return ASTParameter(name: parameterName, type: nil, at: parameterNameLocation)
            default:
                throw ParseError.unexpectedToken("unexpected \(token!)")
        }
    }

    public func parseFunctionDefinition() throws -> ASTFunction {
        let prototype = try parseFunctionPrototype()
        var body = [ASTStatement]()

        try skipOptionalToken(.newline)
        try skipExpectedToken(.leftBrace)
        try skipOptionalToken(.newline)

        while token != .rightBrace {
            body.append(try parseStatement())
            try skipOptionalToken(.newline)
        }
        try skipExpectedToken(.rightBrace)

        return ASTFunction(prototype: prototype, body: body)
    }

    public func parseExternFunctionDeclaration() throws -> ASTPrototype {
        _ = try nextToken() // consume 'extern'
        return try parseFunctionPrototype(isExtern: true)
    }

    private func parseIntegerLiteral() throws -> ASTExpression {
        guard case .integerLiteral(let value)? = token else { fatalError() }
        let e = ASTIntegerLiteral(value: value, at: tokenSourceLocation)
        _ = try nextToken() // consume the literal
        return e
    }

    private func parseBooleanLiteral() throws -> ASTExpression {
        let e: ASTExpression
        switch token {
            case .keyword(.true)?: e = ASTBooleanLiteral(value: true, at: tokenSourceLocation)
            case .keyword(.false)?: e = ASTBooleanLiteral(value: false, at: tokenSourceLocation)
            default: preconditionFailure()
        }
        _ = try nextToken() // consume the literal
        return e
    }

    private func parseFloatingPointLiteral() throws -> ASTExpression {
        guard case .floatingPointLiteral(let value)? = token else { fatalError() }
        let e = ASTFloatingPointLiteral(value: value, at: tokenSourceLocation)
        _ = try nextToken() // consume the literal
        return e
    }

    private func parseStringLiteral() throws -> ASTExpression {
        guard case .stringLiteral(let value)? = token else { fatalError() }
        let e = ASTStringLiteral(value: value, at: tokenSourceLocation)
        _ = try nextToken() // consume the literal
        return e
    }

    private func parseNullLiteral() throws -> ASTExpression {
        let e = ASTNullLiteral(at: tokenSourceLocation)
        _ = try nextToken() // consume 'null'
        return e
    }

    private func parseParenthesizedExpression() throws -> ASTExpression {
        _ = try nextToken() // consume '('
        let e = try parseExpression()
        try expectToken(.rightParenthesis)
        _ = try nextToken() // consume ')'
        return e
    }

    private func parseIdentifier() throws -> ASTExpression {
        guard case .identifier(let identifier)? = token else {
            fatalError()
        }

        let identifierSourceLocation = tokenSourceLocation!

        if try nextToken() != .leftParenthesis {
            // It's a variable.
            return ASTVariable(name: identifier, at: identifierSourceLocation)
        }

        // It's a function call.
        var arguments = [ASTExpression]()

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
        return ASTFunctionCall(functionName: identifier, arguments: arguments, at: identifierSourceLocation)
    }

    private func parsePrimaryExpression() throws -> ASTExpression {
        switch token {
            case .identifier?: return try parseIdentifier()
            case .integerLiteral?: return try parseIntegerLiteral()
            case .floatingPointLiteral?: return try parseFloatingPointLiteral()
            case .stringLiteral?: return try parseStringLiteral()
            case .keyword(.null)?: return try parseNullLiteral()
            case .keyword(.true)?, .keyword(.false)?: return try parseBooleanLiteral()
            case .keyword(.if)?: return try parseIfExpression()
            case .leftParenthesis?: return try parseParenthesizedExpression()
            default: throw ParseError.unexpectedToken("unexpected \(token!)")
        }
    }

    public func parseExpression() throws -> ASTExpression {
        return try parseBinOpRHS(precedence: 0, lhs: try parseUnaryExpression())
    }

    private func parseUnaryExpression() throws -> ASTExpression {
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
        return ASTFunctionCall(functionName: unaryOperator.rawValue,
                               arguments: [try parseUnaryExpression()], at: operatorLocation)
    }

    private func parseBinOpRHS(precedence: Int, lhs: ASTExpression) throws -> ASTExpression {
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
            lhs = ASTFunctionCall(functionName: binaryOperator.rawValue,
                                  arguments: [lhs, rhs], at: operatorLocation)
        }
    }

    private func parseIfStatement() throws -> ASTStatement {
        let ifLocation = tokenSourceLocation!
        _ = try nextToken() // consume 'if'
        let condition = try parseExpression()
        try skipOptionalToken(.newline)
        try skipExpectedToken(.leftBrace, "expected `then` or `{` after `if` condition")
        try skipOptionalToken(.newline)
        var thenBranch = [ASTStatement]()
        var elseBranch = [ASTStatement]()

        while token != .rightBrace {
            thenBranch.append(try parseStatement())
            try skipExpectedToken(.newline)
        }

        try skipExpectedToken(.rightBrace)
        try skipOptionalToken(.newline)
        try skipExpectedToken(.keyword(.else))
        try skipOptionalToken(.newline)
        try skipExpectedToken(.leftBrace)
        try skipOptionalToken(.newline)

        while token != .rightBrace {
            elseBranch.append(try parseStatement())
            try skipExpectedToken(.newline)
        }
        try skipExpectedToken(.rightBrace)
        try expectToken(.newline)

        return ASTIfStatement(condition: condition, then: thenBranch, else: elseBranch, at: ifLocation)
    }

    private func parseIfExpression() throws -> ASTExpression {
        let ifLocation = tokenSourceLocation!
        _ = try nextToken() // consume 'if'
        let condition = try parseExpression()
        try expectToken(.keyword(.then), "expected `then` or newline after `if` condition")

        _ = try nextToken() // consume 'then'
        let thenBranch = try parseExpression()
        try expectToken(.keyword(.else))
        _ = try nextToken() // consume 'else'
        let elseBranch = try parseExpression()

        return ASTIfExpression(condition: condition, then: thenBranch, else: elseBranch, at: ifLocation)
    }

    public func parseStatement() throws -> ASTStatement {
        switch token {
            case .keyword(.return)?: return try parseReturnStatement()

            // Handle variable definition.
            case .identifier(let name)?:
                let identifierLocation = tokenSourceLocation!
                let next = try nextToken()
                let nextLocation = tokenSourceLocation!
                if next == .assignmentOperator {
                    _ = try nextToken() // consume `=`
                    return ASTVariableDefinition(name: name, value: try parseExpression(), at: identifierLocation)
                }
                tokens = [(nextLocation, next), (identifierLocation, .identifier(name))]

            // Handle if-statement (if-expression will be handled by `parseExpression` below).
            case .keyword(.if)?:
                let ifLocation = tokenSourceLocation!
                var tempTokens = [(SourceLocation, Token)]()
                repeat {
                    let nextToken = try self.nextToken()
                    tempTokens.append((tokenSourceLocation, nextToken))
                } while tempTokens.last!.1 != .newline && tempTokens.last!.1 != .keyword(.then)
                tokens = tempTokens.reversed() + [(ifLocation, .keyword(.if))]
                if tempTokens.last!.1 == .newline { // It's an if-statement.
                    return try parseIfStatement()
                }

            default: break
        }
        return try parseExpression()
    }

    private func parseReturnStatement() throws -> ASTReturnStatement {
        let returnLocation = tokenSourceLocation!
        _ = try nextToken() // consume 'return'
        return ASTReturnStatement(value: try parseExpression(), at: returnLocation)
    }
}
