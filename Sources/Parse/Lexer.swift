import Foundation
import AST

public enum Keyword: String {
    case `func`
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

    public init(readFrom inputStream: TextInputStream) {
        self.inputStream = inputStream
    }

    func lex() -> Token {
        var character: UnicodeScalar? // `nil` on EOF

        repeat {
            character = inputStream.read()
        } while character == " " || character == "\t"

        // TODO
//        guard let c = character else { return .eof }

        if let c = character, CharacterSet.newlines.contains(c) {
            return .newline
        }

        if let c = character, CharacterSet.letters.contains(c) {
            return lexKeywordOrIdentifier(firstCharacter: c)
        }

        if let c = character, CharacterSet.decimalDigits.contains(c) {
            return lexNumericLiteral(firstCharacter: c)
        }

        func lexOperator(_ a: UnicodeScalar, _ aToken: Token, _ bToken: Token) -> Token? {
            if let c = character, c == a {
                let next = inputStream.read()
                if next == "=" { return bToken }
                inputStream.unread(next)
                return aToken
            }
            return nil
        }

        if let t = lexOperator("=", .binaryOperator(.assignment), .binaryOperator(.equals)) { return t }
        if let t = lexOperator("!", .not, .binaryOperator(.notEquals)) { return t }
        if let t = lexOperator("<", .binaryOperator(.lessThan), .binaryOperator(.lessThanOrEqual)) { return t }
        if let t = lexOperator(">", .binaryOperator(.greaterThan), .binaryOperator(.greaterThanOrEqual)) { return t }

        if let c = character, c == "#" { // comment until end of line
            while true {
                character = inputStream.read()
                guard let c = character else { break }
                guard CharacterSet.newlines.contains(c) else { break }
            }
            if character != nil { return lex() } // TODO: remove recursion
        }

        switch character {
            case nil: return .eof
            case "("?: return .leftParenthesis
            case ")"?: return .rightParenthesis
            case ","?: return .comma
            case "+"?: return .plus
            case "-"?: return .minus
            case "*"?: return .binaryOperator(.multiplication)
            case "/"?: return .binaryOperator(.division)
            default: preconditionFailure()
        }
    }

    private func lexKeywordOrIdentifier(firstCharacter: UnicodeScalar) -> Token {
        var identifier = String.UnicodeScalarView()
        identifier.append(firstCharacter)

        while true {
            let character = inputStream.read()
            if let c = character, CharacterSet.alphanumerics.contains(c) {
                identifier.append(c)
            } else {
                inputStream.unread(character)
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
            character = inputStream.read()
            if let c = character, CharacterSet.decimalDigits.contains(c) || c == "." {
                character = c
                if c == "." { floatingPoint = true }
            } else {
                inputStream.unread(character)
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
