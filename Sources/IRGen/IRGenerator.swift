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
    private var functionPrototypes: [String: FunctionPrototype]
    private var values: [LLVMValueRef?]
    private var returnType: LLVMTypeRef?
    public var functionPassManager: LLVMPassManagerRef?
    public var module: LLVMModuleRef?

    public init(context: LLVMContextRef) {
        self.context = context
        builder = LLVMCreateBuilderInContext(context)
        namedValues = [:]
        functionPrototypes = [:]
        values = []
        returnType = LLVMVoidTypeInContext(context) // dummy initial value
    }

    public var result: LLVMValueRef? {
        return values.last!
    }

    public func visitVariableExpression(name: String) throws {
        guard let namedValue = namedValues[name] else {
            throw IRGenError.unknownIdentifier(message: "unknown variable '\(name)'")
        }
        values.append(LLVMBuildLoad(builder, namedValue, name))
    }

    public func visitUnaryExpression(operator: UnaryOperator, operand: Expression) throws {
        try operand.acceptVisitor(self)

        guard let operandValue = values.last ?? nil else { return /* TODO: Should we simply return here? */ }
        values.removeLast()

        let value: LLVMValueRef
        switch `operator` {
            case .not: value = try buildLogicalNegation(of: operandValue)
            case .plus: value = operandValue
            case .minus: value = try buildNumericNegation(of: operandValue)
        }
        values.append(value)
    }

    public func visitBinaryExpression(operator: BinaryOperator, lhs: Expression, rhs: Expression) throws {
        // Special case for '=' because we don't want to emit lhs as an expression.
        if (`operator` == .assignment) {
            return buildAssignment(operator: `operator`, lhs: lhs, rhs: rhs)
        }

        try lhs.acceptVisitor(self)
        guard let left = values.last ?? nil else { return }
        values.removeLast()

        try rhs.acceptVisitor(self)
        guard let right = values.last ?? nil else { return }
        values.removeLast()

        let v: LLVMValueRef
        switch `operator` {
            case .plus: v = buildBinaryOperation(left, right, LLVMBuildAdd, LLVMBuildFAdd, "addtmp")
            case .minus: v = buildBinaryOperation(left, right, LLVMBuildSub, LLVMBuildFSub, "subtmp")
            case .multiplication: v = buildBinaryOperation(left, right, LLVMBuildMul, LLVMBuildFMul, "multmp")
            case .division: v = buildBinaryOperation(left, right, LLVMBuildSDiv, LLVMBuildFDiv, "divtmp")
            case .equals: v = buildComparisonOperation(left, right, LLVMBuildICmp, LLVMBuildFCmp, LLVMIntEQ, LLVMRealOEQ, "eqltmp")
            case .notEquals: v = buildComparisonOperation(left, right, LLVMBuildICmp, LLVMBuildFCmp, LLVMIntNE, LLVMRealONE, "neqtmp")
            case .greaterThan: v = buildComparisonOperation(left, right, LLVMBuildICmp, LLVMBuildFCmp, LLVMIntSGT, LLVMRealUGT, "cmptmp")
            case .lessThan: v = buildComparisonOperation(left, right, LLVMBuildICmp, LLVMBuildFCmp, LLVMIntSLT, LLVMRealULT, "cmptmp")
            case .greaterThanOrEqual: v = buildComparisonOperation(left, right, LLVMBuildICmp, LLVMBuildFCmp, LLVMIntSGE, LLVMRealUGE, "cmptmp")
            case .lessThanOrEqual: v = buildComparisonOperation(left, right, LLVMBuildICmp, LLVMBuildFCmp, LLVMIntSLE, LLVMRealULE, "cmptmp")
            default: throw IRGenError.unknownIdentifier(message: "unsupported binary operator")
        }

        values.append(v)
    }

    public func visitFunctionCallExpression(functionName: String, arguments: [Expression]) throws {
        guard let function = try? lookupFunction(named: functionName) else {
            throw IRGenError.unknownIdentifier(message: "unknown function name '\(functionName)'")
        }

        if Int(LLVMCountParams(function)) != arguments.count {
            throw IRGenError.argumentMismatch(message: "wrong number of arguments, expected \(LLVMCountParams(function))")
        }

        var argumentValues = [LLVMValueRef?]()
        argumentValues.reserveCapacity(arguments.count)
        for argument in arguments {
            try argument.acceptVisitor(self)
            argumentValues.append(values.removeLast())
        }
        values.append(LLVMBuildCall(builder, function, &argumentValues, UInt32(argumentValues.count), "calltmp"))
    }

    public func visitIntegerLiteralExpression(value: Int64) {
        values.append(LLVMConstInt(LLVMInt64TypeInContext(context), UInt64(value), LLVMFalse))
    }

    public func visitFloatingPointLiteralExpression(value: Float64) {
        values.append(LLVMConstReal(LLVMDoubleTypeInContext(context), value))
    }

    public func visitBooleanLiteralExpression(value: Bool) {
        values.append(LLVMConstInt(LLVMInt1TypeInContext(context), value ? 1 : 0, LLVMFalse))
    }

    public func visitIfExpression(condition: Expression, then: Expression, else: Expression) throws {
        // condition
        try condition.acceptVisitor(self)
        guard var conditionValue = values.last! else { return }
        values.removeLast()

        // Convert condition to a bool by comparing to 0.
        let zeroConstant = LLVMConstReal(LLVMDoubleTypeInContext(context), 0)
        conditionValue = LLVMBuildFCmp(builder, LLVMRealONE, conditionValue, zeroConstant, "ifcond")

        let function = LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder))

        var thenBlock = LLVMAppendBasicBlockInContext(context, function, "then")
        var elseBlock = LLVMAppendBasicBlockInContext(context, function, "else")
        let mergeBlock = LLVMAppendBasicBlockInContext(context, function, "ifcont")

        LLVMBuildCondBr(builder, conditionValue, thenBlock, elseBlock)

        // then
        LLVMPositionBuilderAtEnd(builder, thenBlock)

        try then.acceptVisitor(self)
        guard var thenValue = values.last else { return }
        values.removeLast()

        LLVMBuildBr(builder, mergeBlock)
        thenBlock = LLVMGetInsertBlock(builder)

        // else
        LLVMPositionBuilderAtEnd(builder, elseBlock)

        try `else`.acceptVisitor(self)
        guard var elseValue = values.last else { return }
        values.removeLast()

        LLVMBuildBr(builder, mergeBlock)
        elseBlock = LLVMGetInsertBlock(builder)

        // merge
        LLVMPositionBuilderAtEnd(builder, mergeBlock)
        let phi = LLVMBuildPhi(builder, LLVMDoubleTypeInContext(context), "iftmp")
        LLVMAddIncoming(phi, &thenValue, &thenBlock, 1)
        LLVMAddIncoming(phi, &elseValue, &elseBlock, 1)

        values.append(phi)
    }

    public func visitFunction(_ astFunction: Function) throws {
        let prototype = astFunction.prototype
        functionPrototypes[prototype.name] = astFunction.prototype
        var llvmFunction = try initFunction(astFunction: astFunction, prototype: prototype)

        guard var value = values.last! else {
            // Error reading body, remove function.
            LLVMDeleteFunction(llvmFunction)
            return
        }

        values.removeLast()
        returnType = LLVMTypeOf(value)

        // Recreate function with correct return type.
        LLVMDeleteFunction(llvmFunction)
        llvmFunction = try initFunction(astFunction: astFunction, prototype: prototype)
        value = values.removeLast()!

        LLVMBuildRet(builder, value)
        LLVMVerifyFunction(llvmFunction, LLVMAbortProcessAction)
        LLVMRunFunctionPassManager(functionPassManager, llvmFunction)
        values.append(llvmFunction)
    }

    public func visitFunctionPrototype(_ prototype: FunctionPrototype) {
        var parameterTypes = [LLVMTypeRef?](repeating: LLVMDoubleTypeInContext(context),
                                           count: prototype.parameters.count)
        let functionType = LLVMFunctionType(returnType, &parameterTypes,
                                            UInt32(parameterTypes.count), LLVMFalse)
        let function = LLVMAddFunction(module, prototype.name, functionType)

        // TODO: parameter names

        values.append(function)
    }

    /// Searches `module` for an existing function declaration with the given name,
    /// or, if it doesn't find one, generates a new one from `functionPrototypes`.
    func lookupFunction(named functionName: String) throws -> LLVMValueRef? {
        // First, see if the function has already been added to the current module.
        if let function = LLVMGetNamedFunction(module, functionName) { return function }

        // If not, check whether we can codegen the declaration from some existing prototype.
        if let functionPrototype = functionPrototypes[functionName] {
            try functionPrototype.acceptVisitor(self)
            assert(LLVMGetValueKind(values.last!) == LLVMFunctionValueKind)
            return values.last!!
        }

        return nil // No existing prototype exists.
    }

    private func createParameterAllocas(_ prototype: FunctionPrototype, _ function: LLVMValueRef) {
        // TODO
    }

    private func initFunction(astFunction: Function, prototype: FunctionPrototype) throws -> LLVMValueRef {
        let llvmFunction = try lookupFunction(named: prototype.name)!
        let basicBlock = LLVMAppendBasicBlockInContext(context, llvmFunction, "entry")
        LLVMPositionBuilderAtEnd(builder, basicBlock)
        namedValues.removeAll(keepingCapacity: true)
        createParameterAllocas(prototype, llvmFunction)
        try astFunction.body.acceptVisitor(self)
        return llvmFunction
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

    private func buildAssignment(operator: BinaryOperator, lhs: Expression, rhs: Expression) {
        // TODO
    }
}
