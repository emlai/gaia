import AST
import MIR

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

/// Checks the AST for type errors, building the MIR during the process.
public final class TypeChecker: ASTVisitor {
    private var symbolTable: SymbolTable
    private var arguments: [Type]? // Used to pass function arguments to visitor functions.
    private var returnTypes: [[Type]]
    private var typeCheckedFunctions: [String: Type]
    private var functionsBeingCurrentlyInstantiated: [FunctionSignature: FunctionPrototype]
    private var instantiatedFunctions: [FunctionSignature: Function]

    public init(allowRedefinitions: Bool) {
        symbolTable = SymbolTable(allowRedefinitions: allowRedefinitions)
        returnTypes = []
        typeCheckedFunctions = [:]
        functionsBeingCurrentlyInstantiated = [:]
        instantiatedFunctions = [:]
    }

    public func visit(variable: ASTVariable) throws -> MIRNode? {
        guard let type = symbolTable.lookupVariable(name: variable.name) else {
            throw SemanticError.unknownIdentifier(location: variable.sourceLocation,
                                                  message: "unknown variable '\(variable.name)'")
        }
        return Variable(variable.name, type)
    }

    private func operationAsCall(_ operation: ASTFunctionCall, _ operands: Expression...,
                                     returnType: Type? = nil) -> FunctionCall {
        let returnType = returnType ?? operands[0].type
        let p = FunctionPrototype(name: operation.functionName,
                                  parameters: operands.map { Parameter(name: "operand", type: $0.type) },
                                  returnType: returnType, body: nil)
        return FunctionCall(target: p, arguments: operands, type: returnType)
    }

    private func visit(unaryOperation: ASTFunctionCall) throws -> FunctionCall? {
        let operand = try unaryOperation.arguments[0].acceptVisitor(self) as! Expression
        switch UnaryOperator(rawValue: unaryOperation.functionName)! {
            case .not:
                if operand.type == .bool { return operationAsCall(unaryOperation, operand) }
            case .plus, .minus:
                if [.int, .float].contains(operand.type) { return operationAsCall(unaryOperation, operand) }
        }
        return nil
    }

    private func visit(binaryOperation: ASTFunctionCall) throws -> FunctionCall? {
        let lhs = try binaryOperation.arguments[0].acceptVisitor(self) as! Expression
        let rhs = try binaryOperation.arguments[1].acceptVisitor(self) as! Expression

        switch BinaryOperator(rawValue: binaryOperation.functionName)! {
            case .equals, .notEquals, .lessThan, .lessThanOrEqual, .greaterThan, .greaterThanOrEqual:
                switch (lhs.type, rhs.type) {
                    case (.int, .int), (.bool, .bool), (.float, .float):
                        return operationAsCall(binaryOperation, lhs, rhs, returnType: .bool)
                    case (.float, .int):
                        if binaryOperation.arguments[1] as? ASTIntegerLiteral != nil {
                            return operationAsCall(binaryOperation, lhs, rhs, returnType: .bool)
                        }
                    case (.int, .float):
                        if binaryOperation.arguments[0] as? ASTIntegerLiteral != nil {
                            return operationAsCall(binaryOperation, lhs, rhs, returnType: .bool)
                        }
                    default: break
                }
            case .plus, .minus, .multiplication, .division:
                switch (lhs.type, rhs.type) {
                    case (.int, .int): return operationAsCall(binaryOperation, lhs, rhs, returnType: .int)
                    case (.float, .float): return operationAsCall(binaryOperation, lhs, rhs, returnType: .float)
                    default: break
                }
        }
        return try handleImplicitlyDefinedOperators(binaryOperation) as! FunctionCall?
    }

    private func handleImplicitlyDefinedOperators(_ functionCall: ASTFunctionCall) throws -> MIRNode? {
        // TODO: Clean this up.
        switch BinaryOperator(rawValue: functionCall.functionName)! {
            case .notEquals:
                let equals = ASTFunctionCall(functionName: "==", arguments: functionCall.arguments,
                                             at: functionCall.sourceLocation)
                let negation = ASTFunctionCall(functionName: "!", arguments: [equals],
                                               at: functionCall.sourceLocation)
                return try visit(functionCall: negation)
            case .greaterThan:
                let less = ASTFunctionCall(functionName: "<", arguments: functionCall.arguments.reversed(),
                                           at: functionCall.sourceLocation)
                return try visit(functionCall: less)
            case .lessThanOrEqual:
                let less = ASTFunctionCall(functionName: "<", arguments: functionCall.arguments.reversed(),
                                           at: functionCall.sourceLocation)
                let negation = ASTFunctionCall(functionName: "!", arguments: [less],
                                               at: functionCall.sourceLocation)
                return try visit(functionCall: negation)
            case .greaterThanOrEqual:
                let less = ASTFunctionCall(functionName: "<", arguments: functionCall.arguments,
                                           at: functionCall.sourceLocation)
                let negation = ASTFunctionCall(functionName: "!", arguments: [less],
                                               at: functionCall.sourceLocation)
                return try visit(functionCall: negation)
            default: return nil
        }
    }

    public func visit(functionCall: ASTFunctionCall) throws -> MIRNode? {
        let arguments = try functionCall.arguments.map { try $0.acceptVisitor(self) as! Expression }
        let argumentTypes = arguments.map { $0.type }

        if functionCall.isBinaryOperation {
            if let call = try visit(binaryOperation: functionCall) { return call }
        } else if functionCall.isUnaryOperation {
            if let call = try visit(unaryOperation: functionCall) { return call }
        }

        if let prototype = try getInstantiatedPrototypeForFunctionCall(name: functionCall.functionName,
                                                                       argumentTypes: argumentTypes) {
            return FunctionCall(target: prototype, arguments: arguments,
                                type: prototype.returnType ?? .void)
        }

        if functionCall.isBinaryOperation {
            throw SemanticError.noMatchingFunction(location: functionCall.sourceLocation,
                                                   message: "invalid types `\(argumentTypes[0])` and " +
                                                            "`\(argumentTypes[1])` for binary operation")
        } else if functionCall.isUnaryOperation {
            throw SemanticError.noMatchingFunction(location: functionCall.arguments[0].sourceLocation,
                                                   message: "invalid operand type `\(argumentTypes[0])` " +
                                                            "for unary `\(functionCall.functionName)`")
        }
        let argumentList = "(\(argumentTypes.map { $0.rawValue }.joined(separator: ", ")))"
        throw SemanticError.noMatchingFunction(location: functionCall.sourceLocation,
                                               message: "no matching function `\(functionCall.functionName)` " +
                                                        "to call with argument types \(argumentList)")
    }

    private func getInstantiatedPrototypeForFunctionCall(name: String, argumentTypes: [Type]) throws -> FunctionPrototype? {
        if let beingInstantiated = functionsBeingCurrentlyInstantiated[FunctionSignature(name, argumentTypes)] {
            return beingInstantiated
        }

        if let instantiated = instantiatedFunctions[FunctionSignature(name, argumentTypes)] {
            return instantiated.prototype
        }

        if let function = try symbolTable.lookupFunctionTemplateToCall(name: name, argumentTypes: argumentTypes) {
            self.arguments = argumentTypes
            let scopeBackup = symbolTable.popScope() // Prevent leaking local variables to other functions.
            let instantiatedFunction = try instantiateFunction(function)
            instantiatedFunctions[FunctionSignature(name, argumentTypes)] = instantiatedFunction
            if let scopeBackup = scopeBackup { symbolTable.pushScope(scopeBackup) }
            return instantiatedFunction.prototype
        }

        if let prototype = try symbolTable.lookupExternFunction(name: name, argumentTypes: argumentTypes) {
            return prototype
        }

        return nil
    }

    public func visit(integerLiteral: ASTIntegerLiteral) throws -> MIRNode? {
        return IntegerLiteral(value: integerLiteral.value)
    }

    public func visit(floatingPointLiteral: ASTFloatingPointLiteral) throws -> MIRNode? {
        return FloatingPointLiteral(value: floatingPointLiteral.value)
    }

    public func visit(booleanLiteral: ASTBooleanLiteral) throws -> MIRNode? {
        return BooleanLiteral(value: booleanLiteral.value)
    }

    public func visit(stringLiteral: ASTStringLiteral) throws -> MIRNode? {
        return StringLiteral(value: stringLiteral.value)
    }

    public func visit(nullLiteral: ASTNullLiteral) throws -> MIRNode? {
        return NullLiteral()
    }

    public func visit(ifExpression: ASTIfExpression) throws -> MIRNode? {
        let condition = try ifExpression.condition.acceptVisitor(self) as! Expression
        if condition.type != .bool {
            throw TypeError.invalidType(location: ifExpression.condition.sourceLocation,
                                        message: "'if' condition requires a Bool expression")
        }
        let thenNode = try ifExpression.then.acceptVisitor(self) as! Expression
        let elseNode = try ifExpression.else.acceptVisitor(self) as! Expression
        if thenNode.type != elseNode.type {
            throw TypeError.mismatchingTypes(location: ifExpression.sourceLocation,
                                             message: "'then' and 'else' branches must have same type")
        }
        return IfExpression(condition: condition, then: thenNode, else: elseNode, type: elseNode.type)
    }

    public func visit(ifStatement: ASTIfStatement) throws -> MIRNode? {
        let condition = try ifStatement.condition.acceptVisitor(self) as! Expression
        if condition.type != .bool {
            throw TypeError.invalidType(location: ifStatement.condition.sourceLocation,
                                        message: "'if' condition requires a Bool expression")
        }
        let thenNodes = try ifStatement.then.map { try $0.acceptVisitor(self) as! Statement }
        let elseNodes = try ifStatement.else.map { try $0.acceptVisitor(self) as! Statement }
        return IfStatement(condition: condition, then: thenNodes, else: elseNodes)
    }

    public func visit(function: ASTFunction) throws -> MIRNode? {
        try symbolTable.registerFunction(function)
        return try function.prototype.acceptVisitor(self)
    }

    private func instantiateFunction(_ function: ASTFunction) throws -> Function {
        let argumentTypes = arguments!

        var prototype: FunctionPrototype?
        if let declaredReturnType = function.prototype.returnType {
            let parameters = zip(function.prototype.parameters, argumentTypes).map {
                Parameter(name: $0.name, type: $1)
            }
            prototype = FunctionPrototype(name: function.prototype.name, parameters: parameters,
                                          returnType: Type(rawValue: declaredReturnType), body: nil)
            functionsBeingCurrentlyInstantiated[FunctionSignature(function.prototype.name, argumentTypes)] = prototype
        } else {
            prototype = nil
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
        let body = try function.body.map { try $0.acceptVisitor(self) as! Statement }
        symbolTable.popScope()
        let returnType = returnTypes.removeLast().first ?? .void

        if prototype == nil {
            let parameters = zip(function.prototype.parameters, argumentTypes).map {
                Parameter(name: $0.name, type: $1)
            }
            prototype = FunctionPrototype(name: function.prototype.name, parameters: parameters,
                                          returnType: returnType, body: nil)
        }
        let instantiation = Function(prototype: prototype!, body: body, type: returnType)
        prototype!.body = instantiation
        functionsBeingCurrentlyInstantiated[FunctionSignature(function.prototype.name, argumentTypes)] = nil
        return instantiation
    }

    public func visit(prototype: ASTPrototype) throws -> MIRNode? {
        if prototype.isExtern { try symbolTable.registerExternFunction(prototype) }
        return nil
    }

    public func visit(returnStatement: ASTReturnStatement) throws -> MIRNode? {
        let returnValue: Expression?
        if let returnExpression = returnStatement.value {
            returnValue = (try returnExpression.acceptVisitor(self) as! Expression)
        } else {
            returnValue = nil
        }
        let returnType = returnValue?.type ?? .void
        if !returnTypes.isEmpty { returnTypes[returnTypes.endIndex - 1].append(returnType) }
        return ReturnStatement(value: returnValue)
    }

    public func visit(variableDefinition: ASTVariableDefinition) throws -> MIRNode? {
        let valueNode = try variableDefinition.value.acceptVisitor(self) as! Expression
        try symbolTable.registerVariable(name: variableDefinition.name, type: valueNode.type,
                                         at: variableDefinition.sourceLocation)
        return VariableDefinition(name: variableDefinition.name, value: valueNode)
    }
}
