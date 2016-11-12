import LLVM_C.Analysis
import LLVM_C.Core
import AST

public enum IRGenError: Error {
    case invalidType(String)
    case unknownIdentifier(message: String)
    case argumentMismatch(message: String)
}

let LLVMFalse: LLVMBool = 0
let LLVMTrue: LLVMBool = 1

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
    public var argumentTypes: [LLVMTypeRef]? // Used to pass function arguments to visitor functions.

    public init(context: LLVMContextRef) {
        self.context = context
        builder = LLVMCreateBuilderInContext(context)
        namedValues = [:]
        functionDefinitions = [:]
        externFunctionPrototypes = [:]
        returnType = LLVMVoidTypeInContext(context) // dummy initial value
    }

    public func visitVariableExpression(name: String) throws -> LLVMValueRef {
        guard let namedValue = namedValues[name] else {
            throw IRGenError.unknownIdentifier(message: "unknown variable '\(name)'")
        }
        return LLVMBuildLoad(builder, namedValue, name)
    }

    public func visitUnaryExpression(operator: UnaryOperator, operand: Expression) throws -> LLVMValueRef {
        let operandValue = try operand.acceptVisitor(self)
        switch `operator` {
            case .not: return try buildLogicalNegation(of: operandValue)
            case .plus: return operandValue
            case .minus: return try buildNumericNegation(of: operandValue)
        }
    }

    public func visitBinaryExpression(operator: BinaryOperator, lhs: Expression, rhs: Expression) throws -> LLVMValueRef {
        // Special case for '=' because we don't want to emit lhs as an expression.
        if (`operator` == .assignment) {
            return buildAssignment(operator: `operator`, lhs: lhs, rhs: rhs)
        }

        let left = try lhs.acceptVisitor(self)
        let right = try rhs.acceptVisitor(self)

        switch `operator` {
            case .plus: return buildBinaryOperation(left, right, LLVMBuildAdd, LLVMBuildFAdd, "addtmp")
            case .minus: return buildBinaryOperation(left, right, LLVMBuildSub, LLVMBuildFSub, "subtmp")
            case .multiplication: return buildBinaryOperation(left, right, LLVMBuildMul, LLVMBuildFMul, "multmp")
            case .division: return buildBinaryOperation(left, right, LLVMBuildSDiv, LLVMBuildFDiv, "divtmp")
            case .equals: return buildComparisonOperation(left, right, LLVMBuildICmp, LLVMBuildFCmp, LLVMIntEQ, LLVMRealOEQ, "eqltmp")
            case .notEquals: return buildComparisonOperation(left, right, LLVMBuildICmp, LLVMBuildFCmp, LLVMIntNE, LLVMRealONE, "neqtmp")
            case .greaterThan: return buildComparisonOperation(left, right, LLVMBuildICmp, LLVMBuildFCmp, LLVMIntSGT, LLVMRealUGT, "cmptmp")
            case .lessThan: return buildComparisonOperation(left, right, LLVMBuildICmp, LLVMBuildFCmp, LLVMIntSLT, LLVMRealULT, "cmptmp")
            case .greaterThanOrEqual: return buildComparisonOperation(left, right, LLVMBuildICmp, LLVMBuildFCmp, LLVMIntSGE, LLVMRealUGE, "cmptmp")
            case .lessThanOrEqual: return buildComparisonOperation(left, right, LLVMBuildICmp, LLVMBuildFCmp, LLVMIntSLE, LLVMRealULE, "cmptmp")
            default: throw IRGenError.unknownIdentifier(message: "unsupported binary operator")
        }
    }

    public func visitFunctionCallExpression(functionName: String, arguments: [Expression]) throws -> LLVMValueRef {
        let prototype: FunctionPrototype
        let nonExternFunction: Function?
        if let externPrototype = externFunctionPrototypes[functionName] {
            prototype = externPrototype
            nonExternFunction = nil
        } else if let function = functionDefinitions[functionName] {
            prototype = function.prototype
            nonExternFunction = function
        } else {
            throw IRGenError.unknownIdentifier(message: "unknown function name '\(functionName)'")
        }

        let parameterCount = prototype.parameters.count
        if parameterCount != arguments.count {
            throw IRGenError.argumentMismatch(message: "wrong number of arguments, expected \(parameterCount)")
        }

        var argumentValues = [LLVMValueRef?]()
        argumentValues.reserveCapacity(arguments.count)
        for argument in arguments {
            argumentValues.append(try argument.acceptVisitor(self))
        }

        let insertBlockBackup = LLVMGetInsertBlock(builder)
        self.argumentTypes = argumentValues.map { LLVMTypeOf($0) }

        let callee: LLVMValueRef
        if let function = nonExternFunction {
            callee = try getInstantiation(of: function, for: argumentTypes!)
        } else {
            self.returnType = LLVMVoidType() // TODO: Support non-void extern functions.
            callee = try LLVMGetNamedFunction(module, functionName) ?? prototype.acceptVisitor(self)
        }

        let name = callee.returnType != LLVMVoidType() ? "calltmp" : ""
        LLVMPositionBuilderAtEnd(builder, insertBlockBackup)
        return LLVMBuildCall(builder, callee, &argumentValues, UInt32(argumentValues.count), name)
    }

    /// Returns an instantiation of the given function for the given parameter types,
    /// building a new concrete function if it has not yet been instantiated.
    private func getInstantiation(of function: Function, for parameterTypes: [LLVMTypeRef]) throws -> LLVMValueRef {
        if let generated = LLVMGetNamedFunction(module, function.prototype.name) {
            if LLVMGetParamTypes(LLVMGetElementType(LLVMTypeOf(generated))) == parameterTypes {
                return generated
            }
        }

        // Instantiate the function with the given parameter types.
        self.argumentTypes = parameterTypes
        return try function.acceptVisitor(self)
    }

    public func visitIntegerLiteralExpression(value: Int64) -> LLVMValueRef {
        return LLVMConstInt(LLVMInt64TypeInContext(context), UInt64(value), LLVMFalse)
    }

    public func visitFloatingPointLiteralExpression(value: Float64) -> LLVMValueRef {
        return LLVMConstReal(LLVMDoubleTypeInContext(context), value)
    }

    public func visitBooleanLiteralExpression(value: Bool) -> LLVMValueRef {
        return LLVMConstInt(LLVMInt1TypeInContext(context), value ? 1 : 0, LLVMFalse)
    }

    public func visitIfExpression(condition: Expression, then: Expression, else: Expression) throws -> LLVMValueRef {
        // condition
        let conditionValue = try condition.acceptVisitor(self)
        if LLVMTypeOf(conditionValue) != LLVMInt1TypeInContext(context) {
            throw IRGenError.invalidType("'if' condition requires a Bool expression")
        }

        let function = LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder))

        var thenBlock = LLVMAppendBasicBlockInContext(context, function, "then")
        var elseBlock = LLVMAppendBasicBlockInContext(context, function, "else")
        let mergeBlock = LLVMAppendBasicBlockInContext(context, function, "ifcont")

        LLVMBuildCondBr(builder, conditionValue, thenBlock, elseBlock)

        // then
        LLVMPositionBuilderAtEnd(builder, thenBlock)
        var thenValue: LLVMValueRef? = try then.acceptVisitor(self)
        LLVMBuildBr(builder, mergeBlock)
        thenBlock = LLVMGetInsertBlock(builder)

        // else
        LLVMPositionBuilderAtEnd(builder, elseBlock)
        var elseValue: LLVMValueRef? = try `else`.acceptVisitor(self)
        LLVMBuildBr(builder, mergeBlock)
        elseBlock = LLVMGetInsertBlock(builder)

        if LLVMTypeOf(thenValue) != LLVMTypeOf(elseValue) {
            throw IRGenError.invalidType("'then' and 'else' branches must have same type")
        }

        // merge
        LLVMPositionBuilderAtEnd(builder, mergeBlock)
        let phi = LLVMBuildPhi(builder, LLVMTypeOf(thenValue), "iftmp")
        LLVMAddIncoming(phi, &thenValue, &thenBlock, 1)
        LLVMAddIncoming(phi, &elseValue, &elseBlock, 1)
        return phi!
    }

    public func visitFunction(_ astFunction: Function) throws -> LLVMValueRef {
        let argumentTypes = self.argumentTypes!
        var (llvmFunction, value) = try buildFunctionBody(astFunction: astFunction, argumentTypes: argumentTypes)
        returnType = LLVMTypeOf(value)

        // Recreate function with correct return type.
        LLVMDeleteFunction(llvmFunction)
        (llvmFunction, value) = try buildFunctionBody(astFunction: astFunction, argumentTypes: argumentTypes)

        if LLVMTypeOf(value) == LLVMVoidType() {
            LLVMBuildRetVoid(builder)
        } else {
            LLVMBuildRet(builder, value)
        }
        precondition(LLVMVerifyFunction(llvmFunction, LLVMPrintMessageAction) != 1)
        LLVMRunFunctionPassManager(functionPassManager, llvmFunction)
        return llvmFunction
    }

    public func visitFunctionPrototype(_ prototype: FunctionPrototype) -> LLVMValueRef {
        var parameterTypes = argumentTypes!.map { Optional.some($0) }
        let functionType = LLVMFunctionType(returnType, &parameterTypes,
                                            UInt32(parameterTypes.count), LLVMFalse)
        let function = LLVMAddFunction(module, prototype.name, functionType)
        let parameterValues = LLVMGetParams(function!)

        for (parameter, name) in zip(parameterValues, prototype.parameters.map { $0.name }) {
            LLVMSetValueName(parameter, name)
        }

        return function!
    }

    public func registerFunctionDefinition(_ function: Function) {
        functionDefinitions[function.prototype.name] = function
    }

    public func registerExternFunctionDeclaration(_ prototype: FunctionPrototype) {
        externFunctionPrototypes[prototype.name] = prototype
    }

    /// Searches `module` for an existing function declaration with the given name,
    /// or, if it doesn't find one, generates a new one from `functionDefinitions`.
    func lookupFunction(named functionName: String, argumentTypes: [LLVMTypeRef]) throws -> LLVMValueRef? {
        // First, see if the function has already been added to the current module.
        if let function = LLVMGetNamedFunction(module, functionName) { return function }

        // If not, check whether we can codegen the declaration from some existing prototype.
        if let astFunction = functionDefinitions[functionName] {
            self.argumentTypes = argumentTypes
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

    private func buildFunctionBody(astFunction: Function, argumentTypes: [LLVMTypeRef]) throws
        -> (function: LLVMValueRef, body: LLVMValueRef) {
        let llvmFunction = try lookupFunction(named: astFunction.prototype.name, argumentTypes: argumentTypes)!
        let basicBlock = LLVMAppendBasicBlockInContext(context, llvmFunction, "entry")
        LLVMPositionBuilderAtEnd(builder, basicBlock)
        namedValues.removeAll(keepingCapacity: true)
        createParameterAllocas(astFunction.prototype, llvmFunction)
        do {
            let body = try astFunction.body.acceptVisitor(self)
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

    private func buildNumericNegation(of operand: LLVMValueRef) throws -> LLVMValueRef {
        switch LLVMTypeOf(operand) {
            case LLVMInt64TypeInContext(context): return LLVMBuildNeg(builder, operand, "negtmp")
            case LLVMDoubleTypeInContext(context): return LLVMBuildFNeg(builder, operand, "negtmp")
            default: fatalError("unknown type")
        }
    }

    private func buildLogicalNegation(of operand: LLVMValueRef) throws -> LLVMValueRef {
        if LLVMTypeOf(operand) != LLVMInt1TypeInContext(context) {
            throw IRGenError.invalidType("logical negation requires a Bool operand")
        }
        let falseConstant = LLVMConstInt(LLVMInt1TypeInContext(context), 0, LLVMFalse)
        return LLVMBuildICmp(builder, LLVMIntEQ, operand, falseConstant, "negtmp")
    }

    typealias IntComparisonOperationBuildFunc =
        (LLVMBuilderRef, LLVMIntPredicate, LLVMValueRef, LLVMValueRef, UnsafePointer<CChar>) -> LLVMValueRef!
    typealias RealComparisonOperationBuildFunc =
        (LLVMBuilderRef, LLVMRealPredicate, LLVMValueRef, LLVMValueRef, UnsafePointer<CChar>) -> LLVMValueRef!

    private func buildComparisonOperation(_ lhs: LLVMValueRef, _ rhs: LLVMValueRef,
                                          _ integerOperationBuildFunc: IntComparisonOperationBuildFunc,
                                          _ floatingPointOperationBuildFunc: RealComparisonOperationBuildFunc,
                                          _ integerOperationPredicate: LLVMIntPredicate,
                                          _ floatingPointOperationPredicate: LLVMRealPredicate,
                                          _ name: String) -> LLVMValueRef {
        switch LLVMTypeOf(lhs) {
            case LLVMInt1TypeInContext(context),
                 LLVMInt64TypeInContext(context):
                return integerOperationBuildFunc(builder, integerOperationPredicate, lhs, rhs, name)
            case LLVMDoubleTypeInContext(context):
                return floatingPointOperationBuildFunc(builder, floatingPointOperationPredicate, lhs, rhs, name)
            default:
                fatalError("unknown type")
        }
    }

    typealias BinaryOperationBuildFunc =
        (LLVMBuilderRef, LLVMValueRef, LLVMValueRef, UnsafePointer<CChar>) -> LLVMValueRef!

    private func buildBinaryOperation(_ lhs: LLVMValueRef, _ rhs: LLVMValueRef,
                                      _ integerOperationBuildFunc: BinaryOperationBuildFunc,
                                      _ floatingPointOperationBuildFunc: BinaryOperationBuildFunc,
                                      _ name: String) -> LLVMValueRef {
        switch LLVMTypeOf(lhs) {
            case LLVMInt64TypeInContext(context):
                return integerOperationBuildFunc(builder, lhs, rhs, name)
            case LLVMDoubleTypeInContext(context):
                return floatingPointOperationBuildFunc(builder, lhs, rhs, name)
            default: fatalError("unknown type")
        }
    }

    private func buildAssignment(operator: BinaryOperator, lhs: Expression, rhs: Expression) -> LLVMValueRef {
        fatalError("unimplemented")
        // TODO
    }

    private func createEntryBlockAlloca(for function: LLVMValueRef, name: String, type: LLVMTypeRef) -> LLVMValueRef {
        let temporaryBuilder = LLVMCreateBuilder()
        let entryBlock = LLVMGetEntryBasicBlock(function)
        let entryBlockFirstInstruction = LLVMGetFirstInstruction(entryBlock)
        LLVMPositionBuilder(temporaryBuilder, entryBlock, entryBlockFirstInstruction)
        return LLVMBuildAlloca(temporaryBuilder, type, name)
    }

    public func appendToMainFunction(_ expression: Expression) throws {
        var mainFunction = LLVMGetNamedFunction(module, "main")

        // Create main function if it doesn't exist.
        if mainFunction == nil {
            let mainFunctionType = LLVMFunctionType(LLVMInt32Type(), nil, 0, LLVMFalse)
            mainFunction = LLVMAddFunction(module, "main", mainFunctionType)
            LLVMAppendBasicBlock(mainFunction, "entry")
        }

        if let returnInstruction = LLVMGetLastInstruction(LLVMGetLastBasicBlock(mainFunction)) {
            LLVMInstructionEraseFromParent(returnInstruction)
        }
        LLVMPositionBuilderAtEnd(builder, LLVMGetLastBasicBlock(mainFunction))
        LLVMBuildRet(builder, try expression.acceptVisitor(self))
    }
}

/// Convenience wrapper around `LLVMGetParams` that returns the parameter array.
private func LLVMGetParams(_ function: LLVMValueRef) -> [LLVMValueRef] {
    var parameters = ContiguousArray<LLVMValueRef?>(repeating: nil, count: Int(LLVMCountParams(function)))
    parameters.withUnsafeMutableBufferPointer { LLVMGetParams(function, $0.baseAddress) }
    return parameters.map { $0! }
}

/// Convenience wrapper around `LLVMGetParamTypes` that returns the parameter type array.
private func LLVMGetParamTypes(_ functionType: LLVMTypeRef) -> [LLVMTypeRef] {
    var parameters = ContiguousArray<LLVMTypeRef?>(repeating: nil, count: Int(LLVMCountParamTypes(functionType)))
    parameters.withUnsafeMutableBufferPointer { LLVMGetParamTypes(functionType, $0.baseAddress) }
    return parameters.map { $0! }
}

extension LLVMValueRef {
    var returnType: LLVMTypeRef {
        return LLVMGetReturnType(LLVMGetElementType(LLVMTypeOf(self)))
    }
}
