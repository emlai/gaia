import AST

public enum TypeError: SourceCodeError {
    case mismatchingTypes(location: SourceLocation, message: String)
    case invalidType(location: SourceLocation, message: String)

    public var location: SourceLocation? {
        switch self {
            case .mismatchingTypes(let location, _), .invalidType(let location, _): return location
        }
    }

    public var description: String {
        switch self {
            case .mismatchingTypes(_, let message), .invalidType(_, let message): return message
        }
    }
}

public final class TypeChecker: ASTVisitor {
    private var symbolTable: SymbolTable
    private var arguments: [Type]? // Used to pass function arguments to visitor functions.
    private var returnTypes: [[Type]]
    private var typeCheckedFunctions: [String: Type]

    public init(allowRedefinitions: Bool) {
        symbolTable = SymbolTable(allowRedefinitions: allowRedefinitions)
        returnTypes = []
        typeCheckedFunctions = [:]
    }

    public func visit(variable: Variable) throws -> Type? {
        guard let type = symbolTable.lookupVariable(name: variable.name) else {
            throw SemanticError.unknownIdentifier(location: variable.sourceLocation,
                                                  message: "unknown variable '\(variable.name)'")
        }
        return type
    }

    public func visit(unaryOperation: UnaryOperation) throws -> Type? {
        let operandType = try unaryOperation.operand.acceptVisitor(self)!

        switch unaryOperation.operator {
            case .not: if operandType == .bool { return .bool }
            case .plus, .minus: if [.int, .float].contains(operandType) { return operandType }
        }

        arguments = [operandType]
        guard let function = try symbolTable.lookupFunction(name: unaryOperation.operator.rawValue,
                                                            argumentTypes: arguments!) else {
            throw TypeError.invalidType(location: unaryOperation.operand.sourceLocation,
                                        message: "invalid operand type `\(operandType.rawValue)` " +
                                                 "for unary `\(unaryOperation.operator.rawValue)`")
        }

        unaryOperation.returnType = try function.acceptVisitor(self)
        return unaryOperation.returnType
    }

    public func visit(binaryOperation: BinaryOperation) throws -> Type? {
        let lhsType = try binaryOperation.leftOperand.acceptVisitor(self)!
        let rhsType = try binaryOperation.rightOperand.acceptVisitor(self)!

        switch binaryOperation.operator {
            case .equals, .notEquals, .lessThan, .lessThanOrEqual, .greaterThan, .greaterThanOrEqual:
                switch (lhsType, rhsType) {
                    case (.int, .int), (.bool, .bool), (.float, .float): return .bool
                    case (.float, .int):
                        if binaryOperation.rightOperand as? IntegerLiteral != nil { return .bool }
                    case (.int, .float):
                        if binaryOperation.leftOperand as? IntegerLiteral != nil { return .bool }
                    default: break
                }
            case .plus, .minus, .multiplication, .division:
                switch (lhsType, rhsType) {
                    case (.int, .int): return .int
                    case (.float, .float): return .float
                    default: break
                }
        }

        arguments = [lhsType, rhsType]
        guard let function = try symbolTable.lookupFunction(name: binaryOperation.operator.rawValue,
                                                            argumentTypes: arguments!) else {
            throw TypeError.invalidType(location: binaryOperation.sourceLocation,
                                        message: "invalid types `\(lhsType.rawValue)` and " +
                                                 "`\(rhsType.rawValue)` for binary operation")
        }

        binaryOperation.returnType = try function.acceptVisitor(self)
        return binaryOperation.returnType
    }

    public func visit(functionCall: FunctionCall) throws -> Type? {
        let argumentTypes = try functionCall.arguments.map { try $0.acceptVisitor(self)! }

        if let function = try symbolTable.lookupFunction(name: functionCall.functionName,
                                                         argumentTypes: argumentTypes) {
            arguments = argumentTypes
            let scopeBackup = symbolTable.popScope() // Prevent leaking local variables to other functions.
            functionCall.returnType = try function.acceptVisitor(self)
            if let scopeBackup = scopeBackup { symbolTable.pushScope(scopeBackup) }
            return functionCall.returnType
        }

        if let prototype = try symbolTable.lookupExternFunction(name: functionCall.functionName,
                                                                argumentTypes: argumentTypes) {
            if !argumentsMatch(argumentTypes, prototype) {
                throw SemanticError.argumentMismatch(message: "arguments don't match, expected " +
                                                              "\(prototype.parameters.map { $0.type })")
            }
            functionCall.returnType = prototype.returnType == nil ? .void : Type(rawValue: prototype.returnType!)
            return functionCall.returnType
        }

        let argumentList = "(\(argumentTypes.map { $0.rawValue }.joined(separator: ", ")))"
        throw SemanticError.noMatchingFunction(location: functionCall.sourceLocation,
                                               message: "no matching function to call with " +
                                                        "argument types \(argumentList)")
    }

    public func visit(integerLiteral: IntegerLiteral) throws -> Type? {
        return .int
    }

    public func visit(floatingPointLiteral: FloatingPointLiteral) throws -> Type? {
        return .float
    }

    public func visit(booleanLiteral: BooleanLiteral) throws -> Type? {
        return .bool
    }

    public func visit(stringLiteral: StringLiteral) throws -> Type? {
        return .string
    }

    public func visit(ifExpression: IfExpression) throws -> Type? {
        if try ifExpression.condition.acceptVisitor(self) != .bool {
            throw TypeError.invalidType(location: ifExpression.condition.sourceLocation,
                                        message: "'if' condition requires a Bool expression")
        }
        let thenType = try ifExpression.then.acceptVisitor(self)
        let elseType = try ifExpression.else.acceptVisitor(self)
        if thenType != elseType {
            throw TypeError.mismatchingTypes(location: ifExpression.sourceLocation,
                                             message: "'then' and 'else' branches must have same type")
        }
        return elseType
    }

    public func visit(ifStatement: IfStatement) throws -> Type? {
        if try ifStatement.condition.acceptVisitor(self) != .bool {
            throw TypeError.invalidType(location: ifStatement.condition.sourceLocation,
                                        message: "'if' condition requires a Bool expression")
        }
        for statement in ifStatement.then { _ = try statement.acceptVisitor(self) }
        for statement in ifStatement.else { _ = try statement.acceptVisitor(self) }
        return nil
    }

    public func visit(function: Function) throws -> Type? {
        if let argumentTypes = arguments {
            if let returnType = typeCheckedFunctions[function.prototype.name] { return returnType }
            if let declaredReturnType = function.prototype.returnType {
                typeCheckedFunctions[function.prototype.name] = Type(rawValue: declaredReturnType)! // TODO: error handling
            }

            // Type-checking the function.
            symbolTable.pushScope()
            assert(argumentTypes.count == function.prototype.parameters.count)
            for (argumentType, parameter) in zip(argumentTypes, function.prototype.parameters) {
                try symbolTable.registerVariable(name: parameter.name, type: argumentType,
                                                 at: parameter.sourceLocation)
            }
            self.arguments = nil
            returnTypes.append([])
            for statement in function.body {
                _ = try statement.acceptVisitor(self)
            }
            symbolTable.popScope()
            return returnTypes.removeLast().first ?? .void
        } else {
            try symbolTable.registerFunction(function)
            return nil
        }
    }

    public func visit(prototype: FunctionPrototype) throws -> Type? {
        try symbolTable.registerExternFunction(prototype)
        return nil
    }

    public func visit(returnStatement: ReturnStatement) throws -> Type? {
        let returnType = try returnStatement.value?.acceptVisitor(self)
        if !returnTypes.isEmpty { returnTypes[returnTypes.endIndex - 1].append(returnType!) }
        return returnType
    }

    public func visit(variableDefinition: VariableDefinition) throws -> Type? {
        let type = try variableDefinition.value.acceptVisitor(self)!
        try symbolTable.registerVariable(name: variableDefinition.name, type: type,
                                         at: variableDefinition.sourceLocation)
        return nil
    }

    private func argumentsMatch(_ argumentTypes: [Type], _ prototype: FunctionPrototype) -> Bool {
        let parameterTypes = prototype.parameters.map { $0.type == nil ? nil : Type(rawValue: $0.type!) }
        if parameterTypes.count != argumentTypes.count { return false }
        for (parameterType, argumentType) in zip(parameterTypes, argumentTypes) {
            if parameterType == nil || parameterType == argumentType {
                return true
            }
        }
        return false
    }
}
