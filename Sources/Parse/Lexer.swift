import Foundation
import AST

public enum Keyword: String {
    case function
    case extern
    case `if`
    case `then`
    case `else`
    case `true`
    case `false`
    case `return`
    case null
}

public enum Token: Equatable, CustomStringConvertible {
    case eof
    case newline
    case identifier(String)
    case integerLiteral(Int64)
    case floatingPointLiteral(Float64)
    case stringLiteral(String)
    case leftBrace
    case rightBrace
    case leftParenthesis
    case rightParenthesis
    case assignmentOperator
    case colon
    case comma
    case arrow
    case keyword(Keyword)
    case not
    case plus
    case minus
    case binaryOperator(BinaryOperator)

    var isPrimary: Bool {
        switch self {
            case .eof, .keyword, .integerLiteral, .floatingPointLiteral, .stringLiteral,
                 .identifier: return true
            default: return false
        }
    }

    var precedence: Int {
        if let binaryOperator = BinaryOperator(from: self) {
            return binaryOperator.precedence
        }
        return -1
    }

    public static func ==(lhs: Token, rhs: Token) -> Bool {
        switch (lhs, rhs) {
            case (.eof, .eof): return true
            case (.newline, .newline): return true
            case (.identifier, .identifier): return true
            case (.integerLiteral, .integerLiteral): return true
            case (.stringLiteral, .stringLiteral): return true
            case (.leftBrace, .leftBrace): return true
            case (.rightBrace, .rightBrace): return true
            case (.leftParenthesis, .leftParenthesis): return true
            case (.rightParenthesis, .rightParenthesis): return true
            case (.assignmentOperator, .assignmentOperator): return true
            case (.colon, .colon): return true
            case (.comma, .comma): return true
            case (.arrow, .arrow): return true
            case (.keyword(let a), .keyword(let b)): return a == b
            case (.not, .not): return true
            case (.plus, .plus): return true
            case (.minus, .minus): return true
            case (.binaryOperator(let a), .binaryOperator(let b)): return a == b
            default: return false
        }
    }

    /// A textual representation of this token.
    public var description: String {
        switch self {
            case .eof: return "EOF"
            case .newline: return "newline"
            case .identifier(let value): return "`\(value)`"
            case .integerLiteral(let value): return "`\(value)`"
            case .floatingPointLiteral(let value): return "`\(value)`"
            case .stringLiteral(let value): return "`\"\(value)\"`"
            case .leftBrace: return "`{`"
            case .rightBrace: return "`}`"
            case .leftParenthesis: return "`(`"
            case .rightParenthesis: return "`)`"
            case .assignmentOperator: return "`=`"
            case .colon: return "`:`"
            case .comma: return "`,`"
            case .arrow: return "`->`"
            case .keyword(let keyword): return "`\(keyword)`"
            case .not: return "`!`"
            case .plus: return "`+`"
            case .minus: return "`-`"
            case .binaryOperator(let op): return "`\(op)`"
        }
    }
}

extension BinaryOperator {
    init?(from token: Token) {
        switch token {
            case .binaryOperator(let op): self = op
            case .plus: self = .plus // FIXME: Can be both unary and binary.
            case .minus: self = .minus // FIXME: Can be both unary and binary.
            default: return nil
        }
    }
}

final class Lexer {
    private let inputStream: TextInputStream
    private var currentSourceLocation: SourceLocation
    private var previousSourceLocation: SourceLocation?

    public init(readFrom inputStream: TextInputStream) {
        self.inputStream = inputStream
        currentSourceLocation = SourceLocation(line: 1, column: 0)
    }

    /// Reads and returns the next unicode scalar (or `nil` on EOF) from the input stream,
    /// updating `currentSourceLocation` and `previousSourceLocation` appropriately.
    private func readNextInputCharacter() -> UnicodeScalar? {
        previousSourceLocation = currentSourceLocation
        let character = inputStream.read()
        switch character {
            case "\n"?: currentSourceLocation.advanceToNextLine()
            default: currentSourceLocation.advanceToNextColumn()
        }
        return character
    }

    /// Puts the given character (or EOF if `nil`) to the beginning of the input stream,
    /// updating `currentSourceLocation` and `previousSourceLocation` appropriately.
    private func unreadInputCharacter(_ character: UnicodeScalar?) {
        currentSourceLocation = previousSourceLocation!
        previousSourceLocation = nil
        inputStream.unread(character)
    }

    func lex() throws -> (SourceLocation, Token) {
        var character: UnicodeScalar? // `nil` on EOF

        repeat {
            character = readNextInputCharacter()
        } while character == " " || character == "\t"

        if let c = character, CharacterSet.newlines.contains(c) {
            return (currentSourceLocation, .newline)
        }

        if let c = character, CharacterSet.letters.contains(c) || c == "_" {
            return (currentSourceLocation, lexKeywordOrIdentifier(firstCharacter: c))
        }

        if let c = character, CharacterSet.decimalDigits.contains(c) {
            return (currentSourceLocation, lexNumericLiteral(firstCharacter: c))
        }

        if let c = character, c == "\"" {
            return (currentSourceLocation, try lexStringLiteral())
        }

        func lexOperator(_ a: UnicodeScalar, _ aToken: Token, _ bToken: Token) -> (SourceLocation, Token)? {
            if let c = character, c == a {
                let location = currentSourceLocation
                let next = readNextInputCharacter()
                if next == "=" { return (location, bToken) }
                unreadInputCharacter(next)
                return (location, aToken)
            }
            return nil
        }

        if let result = lexOperator("=", .assignmentOperator, .binaryOperator(.equals)) {
            return result
        }
        if let result = lexOperator("!", .not, .binaryOperator(.notEquals)) {
            return result
        }
        if let result = lexOperator("<", .binaryOperator(.lessThan), .binaryOperator(.lessThanOrEqual)) {
            return result
        }
        if let result = lexOperator(">", .binaryOperator(.greaterThan), .binaryOperator(.greaterThanOrEqual)) {
            return result
        }

        if let c = character, c == "/" {
            let next = readNextInputCharacter()
            if next == "*" { // `/*` == start of block comment
                try skipBlockComment()
                return try lex() // TODO: remove recursion
            }
            unreadInputCharacter(next)
        }

        switch character {
            case nil: return (currentSourceLocation, .eof)
            case "{"?: return (currentSourceLocation, .leftBrace)
            case "}"?: return (currentSourceLocation, .rightBrace)
            case "("?: return (currentSourceLocation, .leftParenthesis)
            case ")"?: return (currentSourceLocation, .rightParenthesis)
            case ":"?: return (currentSourceLocation, .colon)
            case ","?: return (currentSourceLocation, .comma)
            case "+"?: return (currentSourceLocation, .plus)
            case "-"?:
                let location = currentSourceLocation
                let next = readNextInputCharacter()
                if next == ">" { return (location, .arrow) }
                unreadInputCharacter(next)
                return (location, .minus)
            case "*"?: return (currentSourceLocation, .binaryOperator(.multiplication))
            case "/"?: return (currentSourceLocation, .binaryOperator(.division))
            default: preconditionFailure()
        }
    }

    private func lexKeywordOrIdentifier(firstCharacter: UnicodeScalar) -> Token {
        var identifier = String.UnicodeScalarView()
        identifier.append(firstCharacter)

        while true {
            let character = readNextInputCharacter()
            if let c = character, CharacterSet.alphanumerics.contains(c) || c == "_" {
                identifier.append(c)
            } else {
                unreadInputCharacter(character)
                break
            }
        }

        let identifierString = String(identifier)
        if let keyword = Keyword(rawValue: identifierString) {
            return .keyword(keyword)
        } else {
            return .identifier(identifierString)
        }
    }

    private func lexNumericLiteral(firstCharacter: UnicodeScalar) -> Token {
        var numericLiteral = String.UnicodeScalarView()
        var character: UnicodeScalar? = firstCharacter
        var floatingPoint = false

        while true {
            numericLiteral.append(character!)
            character = readNextInputCharacter()
            if let c = character, CharacterSet.decimalDigits.contains(c) || c == "." {
                character = c
                if c == "." { floatingPoint = true }
            } else {
                unreadInputCharacter(character)
                break
            }
        }

        if floatingPoint {
            return .floatingPointLiteral(Float64(String(numericLiteral))!)
        } else {
            return .integerLiteral(Int64(String(numericLiteral))!)
        }
    }

    private func lexStringLiteral() throws -> Token {
        var value = String.UnicodeScalarView()
        let startLocation = currentSourceLocation

        while true {
            guard let character = readNextInputCharacter() else {
                throw ParseError.unterminatedStringLiteral(location: startLocation)
            }
            if character == "\"" { return .stringLiteral(String(value)) }
            value.append(character)
        }
    }

    private func skipBlockComment() throws {
        while true {
            guard let first = readNextInputCharacter() else {
                throw ParseError.unexpectedToken("expected `*/` before EOF")
            }
            if first == "/" { // Handle nested block comments
                guard let second = readNextInputCharacter() else {
                    throw ParseError.unexpectedToken("expected `*/` before EOF")
                }
                if second == "*" { // start of nested block comment
                    try skipBlockComment()
                    continue
                }
                unreadInputCharacter(second)
                continue
            }
            if first != "*" { continue }
            guard let second = readNextInputCharacter() else {
                throw ParseError.unexpectedToken("expected `*/` before EOF")
            }
            if second == "/" { return } // `*/` == end of block comment
        }
    }
}
