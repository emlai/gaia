import AST

struct SymbolTable {
    struct Scope {
        fileprivate var variableSymbolTable = [String: Type]()
        fileprivate var functionSymbolTable = [String: [Function]]()
        fileprivate var externFunctionSymbolTable = [String: [FunctionPrototype]]()
    }
    private var scopes: [Scope] // scopes[0] == global scope
    private var currentScope: Scope {
        get { return scopes[scopes.endIndex - 1] }
        set { scopes[scopes.endIndex - 1] = newValue }
    }
    private let allowRedefinitions: Bool

    init(allowRedefinitions: Bool = false) {
        scopes = [Scope()]
        self.allowRedefinitions = allowRedefinitions
    }

    mutating func pushScope(_ newScope: Scope = Scope()) {
        scopes.append(newScope)
    }

    @discardableResult
    mutating func popScope() -> Scope? {
        if scopes.count > 1 { // Prevent popping the global scope.
            return scopes.removeLast()
        }
        return nil
    }

    func lookupVariable(name: String) -> Type? {
        for scope in scopes.reversed() {
            if let type = scope.variableSymbolTable[name] {
                return type
            }
        }
        return nil
    }

    func lookupFunction(name: String, argumentTypes: [Type]) throws -> Function? {
        for scope in scopes.reversed() {
            guard var candidates = scope.functionSymbolTable[name] else { continue }
            candidates = candidates.filter{ $0.prototype.parameters.count == argumentTypes.count }
            if argumentTypes.count == 0 { return candidates.first }

            for candidate in candidates {
                let parameterTypes = candidate.prototype.parameters.map { $0.type == nil ? nil : Type(rawValue: $0.type!) }

                for (parameterType, argumentType) in zip(parameterTypes, argumentTypes) {
                    if parameterType == nil || parameterType == argumentType {
                        return candidate
                    }
                }
            }
        }
        return nil
    }

    func lookupExternFunction(name: String, argumentTypes: [Type]) throws -> FunctionPrototype? {
        for scope in scopes.reversed() {
            guard var candidates = scope.externFunctionSymbolTable[name] else { continue }
            candidates = candidates.filter { $0.parameters.count == argumentTypes.count }
            if argumentTypes.count == 0 { return candidates.first }

            for candidate in candidates {
                let parameterTypes = candidate.parameters.map { $0.type == nil ? nil : Type(rawValue: $0.type!) }

                if parameterTypes.count != argumentTypes.count {
                    throw SemanticError.argumentMismatch(message: "wrong number of arguments, " +
                                                                  "expected \(parameterTypes.count)")
                }

                for (parameterType, argumentType) in zip(parameterTypes, argumentTypes) {
                    if parameterType == nil || parameterType == argumentType {
                        return candidate
                    }
                }
            }
        }
        return nil
    }

    mutating func registerVariable(name: String, type: Type, at sourceLocation: SourceLocation) throws {
        if currentScope.variableSymbolTable[name] != nil && !allowRedefinitions {
            throw SemanticError.redefinition(location: sourceLocation,
                                             message: "redefinition of `\(name)`")
        }
        currentScope.variableSymbolTable[name] = type
    }

    mutating func registerFunction(_ function: Function) throws {
        if currentScope.functionSymbolTable[function.prototype.name] != nil && !allowRedefinitions {
            throw SemanticError.redefinition(location: function.sourceLocation,
                                             message: "redefinition of `\(function.prototype.name)`")
        }
        var array = currentScope.functionSymbolTable[function.prototype.name] ?? []
        array.append(function)
        currentScope.functionSymbolTable[function.prototype.name] = array
    }

    mutating func registerExternFunction(_ prototype: FunctionPrototype) throws {
        if currentScope.externFunctionSymbolTable[prototype.name] != nil && !allowRedefinitions {
            throw SemanticError.redefinition(location: prototype.sourceLocation,
                                             message: "redefinition of `\(prototype.name)`")
        }
        var array = currentScope.externFunctionSymbolTable[prototype.name] ?? []
        array.append(prototype)
        currentScope.externFunctionSymbolTable[prototype.name] = array
    }
}
