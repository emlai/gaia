import Foundation
import AST

public enum Keyword: String {
    case `func`
    case end
    case extern
    case `if`
    case `then`
    case `else`
    case `true`
    case `false`
}

public enum Token: Equatable {
    case eof
    case newline
    case identifier(String)
    case integerLiteral(Int64)
    case floatingPointLiteral(Float64)
    case leftParenthesis
    case rightParenthesis
    case comma
    case keyword(Keyword)
    case not
    case plus
    case minus
    case binaryOperator(BinaryOperator)

    var isPrimary: Bool {
        switch self {
            case .eof, .keyword, .integerLiteral, .floatingPointLiteral, .identifier: return true
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
            case (.leftParenthesis, .leftParenthesis): return true
            case (.rightParenthesis, .rightParenthesis): return true
            case (.comma, .comma): return true
            case (.keyword(let a), .keyword(let b)): return a == b
            case (.not, .not): return true
            case (.plus, .plus): return true
            case (.minus, .minus): return true
            case (.binaryOperator(let a), .binaryOperator(let b)): return a == b
            default: return false
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

    func lex() -> (SourceLocation, Token) {
        var character: UnicodeScalar? // `nil` on EOF

        repeat {
            character = readNextInputCharacter()
        } while character == " " || character == "\t"

        // TODO
//        guard let c = character else { return .eof }

        if let c = character, CharacterSet.newlines.contains(c) {
            return (currentSourceLocation, .newline)
        }

        if let c = character, CharacterSet.letters.contains(c) {
            return (currentSourceLocation, lexKeywordOrIdentifier(firstCharacter: c))
        }

        if let c = character, CharacterSet.decimalDigits.contains(c) {
            return (currentSourceLocation, lexNumericLiteral(firstCharacter: c))
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

        if let result = lexOperator("=", .binaryOperator(.assignment), .binaryOperator(.equals)) {
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

        if let c = character, c == "#" { // comment until end of line
            while true {
                character = readNextInputCharacter()
                guard let c = character else { break }
                guard CharacterSet.newlines.contains(c) else { break }
            }
            if character != nil { return lex() } // TODO: remove recursion
        }

        switch character {
            case nil: return (currentSourceLocation, .eof)
            case "("?: return (currentSourceLocation, .leftParenthesis)
            case ")"?: return (currentSourceLocation, .rightParenthesis)
            case ","?: return (currentSourceLocation, .comma)
            case "+"?: return (currentSourceLocation, .plus)
            case "-"?: return (currentSourceLocation, .minus)
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
            if let c = character, CharacterSet.alphanumerics.contains(c) {
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
}
