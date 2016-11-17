import LLVM_C.Analysis
import LLVM_C.Core
import AST

/// Generates LLVM IR code based on the abstract syntax tree.
public final class IRGenerator: ASTVisitor {
    private let context: LLVMContextRef
    private let builder: LLVMBuilderRef
    private var namedValues: [String: LLVMValueRef]
    private var functionDefinitions: [String: Function]
    private var externFunctionPrototypes: [String: FunctionPrototype]
    private var returnType: LLVMTypeRef?
    public var functionPassManager: LLVMPassManagerRef?
    public var module: LLVMModuleRef?
    public var arguments: [Argument]? // Used to pass function arguments to visitor functions.

    public init(context: LLVMContextRef) {
        self.context = context
        builder = LLVMCreateBuilderInContext(context)
        namedValues = [:]
        functionDefinitions = [:]
        externFunctionPrototypes = [:]
        returnType = LLVMVoidTypeInContext(context) // dummy initial value
    }

    public func visit(variableDefinition: VariableDefinition) throws -> LLVMValueRef {
        let value = try variableDefinition.value.acceptVisitor(self)

        if namedValues[variableDefinition.name] != nil {
            throw IRGenError.redefinition(location: variableDefinition.sourceLocation,
                                          message: "redefinition of `\(variableDefinition.name)`")
        }

        let alloca = LLVMBuildAlloca(builder, LLVMTypeOf(value), variableDefinition.name)
        namedValues[variableDefinition.name] = alloca
        return LLVMBuildStore(builder, value, alloca)
    }

    public func visit(variable: Variable) throws -> LLVMValueRef {
        guard let namedValue = namedValues[variable.name] else {
            throw IRGenError.unknownIdentifier(location: variable.sourceLocation,
                                               message: "unknown variable '\(variable.name)'")
        }
        return LLVMBuildLoad(builder, namedValue, variable.name)
    }

    public func visit(unaryOperation: UnaryOperation) throws -> LLVMValueRef {
        switch unaryOperation.operator {
            case .not: return try buildLogicalNegation(of: unaryOperation.operand)
            case .plus: return try unaryOperation.operand.acceptVisitor(self)
            case .minus: return try buildNumericNegation(of: unaryOperation.operand)
        }
    }

    public func visit(binaryOperation: BinaryOperation) throws -> LLVMValueRef {
        switch binaryOperation.operator {
            case .plus: return try buildBinaryOperation(binaryOperation, LLVMBuildAdd, LLVMBuildFAdd, "addtmp")
            case .minus: return try buildBinaryOperation(binaryOperation, LLVMBuildSub, LLVMBuildFSub, "subtmp")
            case .multiplication: return try buildBinaryOperation(binaryOperation, LLVMBuildMul, LLVMBuildFMul, "multmp")
            case .division: return try buildBinaryOperation(binaryOperation, LLVMBuildSDiv, LLVMBuildFDiv, "divtmp")
            case .equals: return try buildComparisonOperation(binaryOperation, LLVMBuildICmp, LLVMBuildFCmp, LLVMIntEQ, LLVMRealOEQ, "eqltmp")
            case .notEquals: return try buildComparisonOperation(binaryOperation, LLVMBuildICmp, LLVMBuildFCmp, LLVMIntNE, LLVMRealONE, "neqtmp")
            case .greaterThan: return try buildComparisonOperation(binaryOperation, LLVMBuildICmp, LLVMBuildFCmp, LLVMIntSGT, LLVMRealUGT, "cmptmp")
            case .lessThan: return try buildComparisonOperation(binaryOperation, LLVMBuildICmp, LLVMBuildFCmp, LLVMIntSLT, LLVMRealULT, "cmptmp")
            case .greaterThanOrEqual: return try buildComparisonOperation(binaryOperation, LLVMBuildICmp, LLVMBuildFCmp, LLVMIntSGE, LLVMRealUGE, "cmptmp")
            case .lessThanOrEqual: return try buildComparisonOperation(binaryOperation, LLVMBuildICmp, LLVMBuildFCmp, LLVMIntSLE, LLVMRealULE, "cmptmp")
        }
    }

    public func visit(functionCall: FunctionCall) throws -> LLVMValueRef {
        let prototype: FunctionPrototype
        let nonExternFunction: Function?
        if let externPrototype = externFunctionPrototypes[functionCall.functionName] {
            prototype = externPrototype
            nonExternFunction = nil
        } else if let function = functionDefinitions[functionCall.functionName] {
            prototype = function.prototype
            nonExternFunction = function
        } else {
            throw IRGenError.unknownIdentifier(location: functionCall.sourceLocation,
                                               message: "unknown function name '\(functionCall.functionName)'")
        }

        let parameterCount = prototype.parameters.count
        if parameterCount != functionCall.arguments.count {
            throw IRGenError.argumentMismatch(message: "wrong number of arguments, expected \(parameterCount)")
        }

        var argumentValues = [LLVMValueRef?]()
        argumentValues.reserveCapacity(functionCall.arguments.count)
        for argument in functionCall.arguments {
            argumentValues.append(try argument.acceptVisitor(self))
        }

        let insertBlockBackup = LLVMGetInsertBlock(builder)
        self.arguments = zip(argumentValues, functionCall.arguments).map {
            Argument(type: LLVMTypeOf($0.0), sourceLocation: $0.1.sourceLocation)
        }

        let callee: LLVMValueRef
        if let function = nonExternFunction {
            callee = try getInstantiation(of: function, for: arguments!)
        } else {
            self.returnType = LLVMVoidType() // TODO: Support non-void extern functions.
            callee = try LLVMGetNamedFunction(module, functionCall.functionName) ?? prototype.acceptVisitor(self)
        }

        let name = callee.returnType != LLVMVoidType() ? "calltmp" : ""
        LLVMPositionBuilderAtEnd(builder, insertBlockBackup)
        return LLVMBuildCall(builder, callee, &argumentValues, UInt32(argumentValues.count), name)
    }

    /// Returns an instantiation of the given function for the given parameter types,
    /// building a new concrete function if it has not yet been instantiated.
    /// Returns `nil` if the function cannot be instantiated for the given parameter types,
    /// e.g. because of conflicting parameter type constraints.
    private func getInstantiation(of function: Function, for arguments: [Argument]) throws -> LLVMValueRef {
        if let generated = LLVMGetNamedFunction(module, function.prototype.name) {
            if LLVMGetParamTypes(LLVMGetElementType(LLVMTypeOf(generated))) == arguments.map({ $0.type }) {
                return generated
            }
        }

        // Instantiate the function with the given parameter types.
        self.arguments = arguments
        return try function.acceptVisitor(self)
    }

    public func visit(integerLiteral: IntegerLiteral) -> LLVMValueRef {
        return LLVMConstInt(LLVMInt64TypeInContext(context), UInt64(integerLiteral.value), LLVMFalse)
    }

    public func visit(floatingPointLiteral: FloatingPointLiteral) -> LLVMValueRef {
        return LLVMConstReal(LLVMDoubleTypeInContext(context), floatingPointLiteral.value)
    }

    public func visit(booleanLiteral: BooleanLiteral) -> LLVMValueRef {
        return LLVMConstInt(LLVMInt1TypeInContext(context), booleanLiteral.value ? 1 : 0, LLVMFalse)
    }

    public func visit(stringLiteral: StringLiteral) -> LLVMValueRef {
        return stringLiteral.value.withCString { LLVMBuildGlobalStringPtr(builder, $0, "") }
    }

    public func visit(ifStatement: IfStatement) throws -> LLVMValueRef {
        // condition
        let conditionValue = try ifStatement.condition.acceptVisitor(self)
        if LLVMTypeOf(conditionValue) != LLVMInt1TypeInContext(context) {
            throw IRGenError.invalidType(location: ifStatement.condition.sourceLocation,
                                         message: "'if' condition requires a Bool expression")
        }

        let function = LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder))

        let thenBlock = LLVMAppendBasicBlockInContext(context, function, "then")
        let elseBlock = LLVMAppendBasicBlockInContext(context, function, "else")

        LLVMBuildCondBr(builder, conditionValue, thenBlock, elseBlock)

        // then
        LLVMPositionBuilderAtEnd(builder, thenBlock)
        let thenValues = try ifStatement.then.map { try $0.acceptVisitor(self) }
        let lastThenValue = thenValues.last

        // else
        LLVMPositionBuilderAtEnd(builder, elseBlock)
        let elseValues = try ifStatement.else.map { try $0.acceptVisitor(self) }
        let lastElseValue = elseValues.last

        // merge
        if LLVMGetValueKind(lastThenValue) == LLVMInstructionValueKind
        && LLVMGetValueKind(lastElseValue) == LLVMInstructionValueKind
        && LLVMGetInstructionOpcode(lastThenValue) == LLVMRet
        && LLVMGetInstructionOpcode(lastElseValue) == LLVMRet {
            // Both branches return, no need for merge block.
            return lastThenValue! // HACK
        }

        let mergeBlock = LLVMAppendBasicBlockInContext(context, function, "ifcont")!
        LLVMPositionBuilderAtEnd(builder, thenBlock)
        LLVMBuildBr(builder, mergeBlock)
        LLVMPositionBuilderAtEnd(builder, elseBlock)
        LLVMBuildBr(builder, mergeBlock)
        return mergeBlock
    }

    public func visit(ifExpression: IfExpression) throws -> LLVMValueRef {
        // condition
        let conditionValue = try ifExpression.condition.acceptVisitor(self)
        if LLVMTypeOf(conditionValue) != LLVMInt1TypeInContext(context) {
            throw IRGenError.invalidType(location: ifExpression.condition.sourceLocation,
                                         message: "'if' condition requires a Bool expression")
        }

        let function = LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder))

        var thenBlock = LLVMAppendBasicBlockInContext(context, function, "then")
        var elseBlock = LLVMAppendBasicBlockInContext(context, function, "else")

        LLVMBuildCondBr(builder, conditionValue, thenBlock, elseBlock)

        // then
        LLVMPositionBuilderAtEnd(builder, thenBlock)
        var thenValue = Optional.some(try ifExpression.then.acceptVisitor(self))

        // else
        LLVMPositionBuilderAtEnd(builder, elseBlock)
        var elseValue = Optional.some(try ifExpression.else.acceptVisitor(self))

        if LLVMTypeOf(thenValue) != LLVMTypeOf(elseValue) {
            throw IRGenError.invalidType(location: ifExpression.sourceLocation,
                                         message: "'then' and 'else' branches must have same type")
        }

        // merge
        let mergeBlock = LLVMAppendBasicBlockInContext(context, function, "ifcont")
        LLVMPositionBuilderAtEnd(builder, thenBlock)
        LLVMBuildBr(builder, mergeBlock)
        LLVMPositionBuilderAtEnd(builder, elseBlock)
        LLVMBuildBr(builder, mergeBlock)

        LLVMPositionBuilderAtEnd(builder, mergeBlock)
        if LLVMTypeOf(thenValue) == LLVMVoidType() {
            return thenValue! // HACK
        }
        let phi = LLVMBuildPhi(builder, LLVMTypeOf(thenValue), "iftmp")
        LLVMAddIncoming(phi, &thenValue, &thenBlock, 1)
        LLVMAddIncoming(phi, &elseValue, &elseBlock, 1)
        return phi!
    }

    public func visit(function: Function) throws -> LLVMValueRef {
        let arguments = self.arguments!
        var (llvmFunction, body) = try buildFunctionBody(of: function, arguments: arguments)

        if LLVMGetValueKind(body.last!) == LLVMInstructionValueKind
        && LLVMGetInstructionOpcode(body.last!) == LLVMRet {
            let index = LLVMGetNumOperands(body.last!) - 1
            returnType = index < 0 ? LLVMVoidType() : LLVMTypeOf(LLVMGetOperand(body.last, UInt32(index)))
        }

        // Recreate function with correct return type.
        LLVMDeleteFunction(llvmFunction)
        (llvmFunction, body) = try buildFunctionBody(of: function, arguments: arguments)

        if LLVMGetValueKind(body.last!) != LLVMInstructionValueKind
        || LLVMGetInstructionOpcode(body.last!) != LLVMRet {
            LLVMPositionBuilderAtEnd(builder, LLVMGetLastBasicBlock(llvmFunction))
            LLVMBuildRetVoid(builder)
        }
        precondition(LLVMVerifyFunction(llvmFunction, LLVMPrintMessageAction) != 1)
        LLVMRunFunctionPassManager(functionPassManager, llvmFunction)
        return llvmFunction
    }

    public func visit(prototype: FunctionPrototype) throws -> LLVMValueRef {
        var actualParameterTypes = [LLVMTypeRef?]()

        for (argument, declaredParameter) in zip(arguments!, prototype.parameters) {
            if let declaredType = declaredParameter.type {
                let type = LLVMTypeRef(gaiaTypeName: declaredType)! // TODO: error handling
                if argument.type != type {
                    let message = "invalid argument type `\(argument.type.gaiaTypeName)`, expected `\(declaredType)`"
                    throw IRGenError.invalidType(location: argument.sourceLocation, message: message)
                }
                actualParameterTypes.append(type)
            } else {
                actualParameterTypes.append(argument.type)
            }
        }

        if let declaredReturnType = prototype.returnType {
            returnType = LLVMTypeRef(gaiaTypeName: declaredReturnType)! // TODO: error handling
        }
        let functionType = LLVMFunctionType(returnType, &actualParameterTypes,
                                            UInt32(actualParameterTypes.count), LLVMFalse)
        let function = LLVMAddFunction(module, prototype.name, functionType)
        let parameterValues = LLVMGetParams(function!)

        for (parameter, name) in zip(parameterValues, prototype.parameters.map { $0.name }) {
            LLVMSetValueName(parameter, name)
        }

        return function!
    }

    public func visit(returnStatement: ReturnStatement) throws -> LLVMValueRef {
        guard let expression = returnStatement.value else { return LLVMBuildRetVoid(builder) }
        let value = try expression.acceptVisitor(self)
        if LLVMTypeOf(value) != LLVMVoidType() { return LLVMBuildRet(builder, value) }
        return LLVMBuildRetVoid(builder) // TODO: don't allow returning void expressions
    }

    public func registerFunctionDefinition(_ function: Function) {
        functionDefinitions[function.prototype.name] = function
    }

    public func registerExternFunctionDeclaration(_ prototype: FunctionPrototype) {
        externFunctionPrototypes[prototype.name] = prototype
    }

    /// Searches `module` for an existing function declaration with the given name,
    /// or, if it doesn't find one, generates a new one from `functionDefinitions`.
    func lookupFunction(named functionName: String, arguments: [Argument]) throws -> LLVMValueRef? {
        // First, see if the function has already been added to the current module.
        if let function = LLVMGetNamedFunction(module, functionName) {
            if LLVMGetParamTypes(LLVMGetElementType(LLVMTypeOf(function))) == arguments.map({ $0.type }) {
                return function
            }
        }

        // If not, check whether we can codegen the declaration from some existing prototype.
        if let astFunction = functionDefinitions[functionName] {
            self.arguments = arguments
            let function = try astFunction.prototype.acceptVisitor(self)
            assert(LLVMGetValueKind(function) == LLVMFunctionValueKind)
            return function
        }

        return nil // No existing prototype exists.
    }

    private func createParameterAllocas(_ prototype: FunctionPrototype, _ function: LLVMValueRef) {
        for (parameter, parameterValue) in zip(prototype.parameters, LLVMGetParams(function)) {
            let alloca = createEntryBlockAlloca(for: function, name: parameter.name, type: LLVMTypeOf(parameterValue))
            LLVMBuildStore(builder, parameterValue, alloca)
            namedValues[parameter.name] = alloca
        }
    }

    private func buildFunctionBody(of astFunction: Function, arguments: [Argument]) throws
        -> (function: LLVMValueRef, body: [LLVMValueRef]) {
        let llvmFunction = try lookupFunction(named: astFunction.prototype.name, arguments: arguments)!
        let basicBlock = LLVMAppendBasicBlockInContext(context, llvmFunction, "entry")
        LLVMPositionBuilderAtEnd(builder, basicBlock)
        let namedValuesBackup = namedValues
        namedValues.removeAll(keepingCapacity: true)
        createParameterAllocas(astFunction.prototype, llvmFunction)
        do {
            let body = try astFunction.body.map { try $0.acceptVisitor(self) }
            namedValues = namedValuesBackup
            return (llvmFunction, body)
        } catch {
            // Error reading body, remove function.
            LLVMDeleteFunction(llvmFunction)
            throw error
        }
    }

    private func buildBoolToDouble(from boolean: LLVMValueRef) -> LLVMValueRef {
        return LLVMBuildUIToFP(builder, boolean, LLVMDoubleTypeInContext(context), "booltmp")
    }

    private func buildNumericNegation(of expression: Expression) throws -> LLVMValueRef {
        let operand = try expression.acceptVisitor(self)

        switch LLVMTypeOf(operand) {
            case LLVMInt64TypeInContext(context): return LLVMBuildNeg(builder, operand, "negtmp")
            case LLVMDoubleTypeInContext(context): return LLVMBuildFNeg(builder, operand, "negtmp")
            default: fatalError("unknown type")
        }
    }

    private func buildLogicalNegation(of expression: Expression) throws -> LLVMValueRef {
        let operand = try expression.acceptVisitor(self)

        if LLVMTypeOf(operand) != LLVMInt1TypeInContext(context) {
            throw IRGenError.invalidType(location: expression.sourceLocation,
                                         message: "logical negation requires a Bool operand")
        }
        let falseConstant = LLVMConstInt(LLVMInt1TypeInContext(context), 0, LLVMFalse)
        return LLVMBuildICmp(builder, LLVMIntEQ, operand, falseConstant, "negtmp")
    }

    typealias IntComparisonOperationBuildFunc =
        (LLVMBuilderRef, LLVMIntPredicate, LLVMValueRef, LLVMValueRef, UnsafePointer<CChar>) -> LLVMValueRef!
    typealias RealComparisonOperationBuildFunc =
        (LLVMBuilderRef, LLVMRealPredicate, LLVMValueRef, LLVMValueRef, UnsafePointer<CChar>) -> LLVMValueRef!

    private func buildComparisonOperation(_ operation: BinaryOperation,
                                          _ integerOperationBuildFunc: IntComparisonOperationBuildFunc,
                                          _ floatingPointOperationBuildFunc: RealComparisonOperationBuildFunc,
                                          _ integerOperationPredicate: LLVMIntPredicate,
                                          _ floatingPointOperationPredicate: LLVMRealPredicate,
                                          _ name: String) throws -> LLVMValueRef {
        let lhs = try operation.leftOperand.acceptVisitor(self)
        let rhs = try operation.rightOperand.acceptVisitor(self)

        switch (LLVMTypeOf(lhs), LLVMTypeOf(rhs)) {
            case (LLVMInt1Type(), LLVMInt1Type()),
                 (LLVMInt64Type(), LLVMInt64Type()):
                return integerOperationBuildFunc(builder, integerOperationPredicate, lhs, rhs, name)
            case (LLVMDoubleType(), LLVMDoubleType()):
                return floatingPointOperationBuildFunc(builder, floatingPointOperationPredicate, lhs, rhs, name)
            default:
                throw IRGenError.invalidType(location: operation.sourceLocation,
                                             message: "invalid types `\(LLVMTypeOf(lhs).gaiaTypeName)` and " +
                                                      "`\(LLVMTypeOf(rhs).gaiaTypeName)` for comparison operation")
        }
    }

    typealias BinaryOperationBuildFunc =
        (LLVMBuilderRef, LLVMValueRef, LLVMValueRef, UnsafePointer<CChar>) -> LLVMValueRef!

    private func buildBinaryOperation(_ operation: BinaryOperation,
                                      _ integerOperationBuildFunc: BinaryOperationBuildFunc,
                                      _ floatingPointOperationBuildFunc: BinaryOperationBuildFunc,
                                      _ name: String) throws -> LLVMValueRef {
        let lhs = try operation.leftOperand.acceptVisitor(self)
        let rhs = try operation.rightOperand.acceptVisitor(self)

        switch (LLVMTypeOf(lhs), LLVMTypeOf(rhs)) {
            case (LLVMInt64Type(), LLVMInt64Type()):
                return integerOperationBuildFunc(builder, lhs, rhs, name)
            case (LLVMDoubleType(), LLVMDoubleType()):
                return floatingPointOperationBuildFunc(builder, lhs, rhs, name)
            default:
                throw IRGenError.invalidType(location: operation.sourceLocation,
                                             message: "invalid types `\(LLVMTypeOf(lhs).gaiaTypeName)` and " +
                                                      "`\(LLVMTypeOf(rhs).gaiaTypeName)` for arithmetic operation")
        }
    }

    private func createEntryBlockAlloca(for function: LLVMValueRef, name: String, type: LLVMTypeRef) -> LLVMValueRef {
        let temporaryBuilder = LLVMCreateBuilder()
        let entryBlock = LLVMGetEntryBasicBlock(function)
        let entryBlockFirstInstruction = LLVMGetFirstInstruction(entryBlock)
        LLVMPositionBuilder(temporaryBuilder, entryBlock, entryBlockFirstInstruction)
        return LLVMBuildAlloca(temporaryBuilder, type, name)
    }

    public func appendToMainFunction(_ statement: Statement) throws {
        if let returnInstruction = LLVMGetLastInstruction(LLVMGetLastBasicBlock(getMainFunction())) {
            LLVMInstructionEraseFromParent(returnInstruction)
        }
        LLVMPositionBuilderAtEnd(builder, LLVMGetLastBasicBlock(getMainFunction()))
        LLVMBuildRet(builder, try statement.acceptVisitor(self))
    }

    /// Creates a `return 0` statement at the end of `main` if it doesn't already have a return statement.
    public func appendImplicitZeroReturnToMainFunction() {
        if LLVMGetLastInstruction(LLVMGetLastBasicBlock(getMainFunction())) != nil { return }
        LLVMPositionBuilderAtEnd(builder, LLVMGetLastBasicBlock(getMainFunction()))
        LLVMBuildRet(builder, LLVMConstInt(LLVMInt64Type(), 0, LLVMFalse))
    }

    private func getMainFunction() -> LLVMValueRef {
        if let mainFunction = LLVMGetNamedFunction(module, "main") { return mainFunction }

        // Create main function if it doesn't exist.
        let mainFunctionType = LLVMFunctionType(LLVMInt32Type(), nil, 0, LLVMFalse)
        let mainFunction = LLVMAddFunction(module, "main", mainFunctionType)!
        LLVMAppendBasicBlock(mainFunction, "entry")
        return mainFunction
    }
}
