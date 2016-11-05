import Foundation
import AST

public enum Keyword: String {
    case `func`
    case `if`
    case `else`
    case `true`
    case `false`
}

public enum Token: Equatable {
    case eof
    case newline
    case identifier(String)
    case integerLiteral(Int64)
    case leftParenthesis
    case rightParenthesis
    case comma
    case keyword(Keyword)
    case unaryOperator(UnaryOperator)
    case binaryOperator(BinaryOperator)

    var isPrimary: Bool {
        switch self {
            case .eof, .keyword, .integerLiteral, .identifier: return true
            default: return false
        }
    }

    var precedence: Int {
        switch self {
            case .binaryOperator(let op): return op.precedence
            default: return -1
        }
    }

    public static func ==(lhs: Token, rhs: Token) -> Bool {
        switch (lhs, rhs) {
            case (.eof, .eof): return true
            case (.identifier, .identifier): return true
            case (.integerLiteral, .integerLiteral): return true
            case (.leftParenthesis, .leftParenthesis): return true
            case (.rightParenthesis, .rightParenthesis): return true
            case (.comma, .comma): return true
            case (.keyword(let a), .keyword(let b)): return a == b
            case (.unaryOperator(let a), .unaryOperator(let b)): return a == b
            case (.binaryOperator(let a), .binaryOperator(let b)): return a == b
            default: return false
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
            return lexIntegerLiteral(firstCharacter: c)
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
        if let t = lexOperator("!", .unaryOperator(.not), .binaryOperator(.notEquals)) { return t }
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
            case "+"?: return .binaryOperator(.plus) // TODO: can be a unary operator too
            case "-"?: return .binaryOperator(.minus) // TODO: can be a unary operator too
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

    private func lexIntegerLiteral(firstCharacter: UnicodeScalar) -> Token {
        var integerLiteral = String.UnicodeScalarView()
        var character: UnicodeScalar? = firstCharacter
        while true {
            integerLiteral.append(character!)
            character = inputStream.read()
            if let c = character, CharacterSet.decimalDigits.contains(c) {
                character = c
            } else {
                inputStream.unread(character)
                break
            }
        }
        return .integerLiteral(Int64(String(integerLiteral))!)
    }
}
