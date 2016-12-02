import AST

public enum SemanticError: SourceCodeError {
    case unknownIdentifier(location: SourceLocation, message: String)
    case argumentMismatch(message: String)
    case redefinition(location: SourceLocation, message: String)
    case noMatchingFunction(location: SourceLocation, message: String)

    public var location: SourceLocation? {
        switch self {
            case .unknownIdentifier(let location, _), .redefinition(let location, _),
                 .noMatchingFunction(let location, _):
                return location
            case .argumentMismatch:
                return nil
        }
    }

    public var description: String {
        switch self {
            case .unknownIdentifier(_, let message), .redefinition(_, let message),
                 .argumentMismatch(let message), .noMatchingFunction(_, let message):
                return message
        }
    }
}
