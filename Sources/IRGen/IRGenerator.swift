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
    private var returnType: LLVMTypeRef?
    public var functionPassManager: LLVMPassManagerRef?
    public var module: LLVMModuleRef?

    public init(context: LLVMContextRef) {
        self.context = context
        builder = LLVMCreateBuilderInContext(context)
        namedValues = [:]
        functionPrototypes = [:]
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
        guard let function = try? lookupFunction(named: functionName) else {
            throw IRGenError.unknownIdentifier(message: "unknown function name '\(functionName)'")
        }

        if Int(LLVMCountParams(function)) != arguments.count {
            throw IRGenError.argumentMismatch(message: "wrong number of arguments, expected \(LLVMCountParams(function))")
        }

        var argumentValues = [LLVMValueRef?]()
        argumentValues.reserveCapacity(arguments.count)
        for argument in arguments {
            argumentValues.append(try argument.acceptVisitor(self))
        }
        return LLVMBuildCall(builder, function, &argumentValues, UInt32(argumentValues.count), "calltmp")
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
        let prototype = astFunction.prototype
        functionPrototypes[prototype.name] = astFunction.prototype
        var (llvmFunction, value) = try initFunction(astFunction: astFunction, prototype: prototype)
        returnType = LLVMTypeOf(value)

        // Recreate function with correct return type.
        LLVMDeleteFunction(llvmFunction)
        (llvmFunction, value) = try initFunction(astFunction: astFunction, prototype: prototype)

        LLVMBuildRet(builder, value)
        LLVMVerifyFunction(llvmFunction, LLVMAbortProcessAction)
        LLVMRunFunctionPassManager(functionPassManager, llvmFunction)
        return llvmFunction
    }

    public func visitFunctionPrototype(_ prototype: FunctionPrototype) -> LLVMValueRef {
        var parameterTypes = [LLVMTypeRef?](repeating: LLVMDoubleTypeInContext(context),
                                           count: prototype.parameters.count)
        let functionType = LLVMFunctionType(returnType, &parameterTypes,
                                            UInt32(parameterTypes.count), LLVMFalse)
        let function = LLVMAddFunction(module, prototype.name, functionType)

        // TODO: parameter names

        return function!
    }

    /// Searches `module` for an existing function declaration with the given name,
    /// or, if it doesn't find one, generates a new one from `functionPrototypes`.
    func lookupFunction(named functionName: String) throws -> LLVMValueRef? {
        // First, see if the function has already been added to the current module.
        if let function = LLVMGetNamedFunction(module, functionName) { return function }

        // If not, check whether we can codegen the declaration from some existing prototype.
        if let functionPrototype = functionPrototypes[functionName] {
            let function = try functionPrototype.acceptVisitor(self)
            assert(LLVMGetValueKind(function) == LLVMFunctionValueKind)
            return function
        }

        return nil // No existing prototype exists.
    }

    private func createParameterAllocas(_ prototype: FunctionPrototype, _ function: LLVMValueRef) {
        // TODO
    }

    private func initFunction(astFunction: Function, prototype: FunctionPrototype) throws
        -> (function: LLVMValueRef, body: LLVMValueRef) {
        let llvmFunction = try lookupFunction(named: prototype.name)!
        let basicBlock = LLVMAppendBasicBlockInContext(context, llvmFunction, "entry")
        LLVMPositionBuilderAtEnd(builder, basicBlock)
        namedValues.removeAll(keepingCapacity: true)
        createParameterAllocas(prototype, llvmFunction)
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
}
