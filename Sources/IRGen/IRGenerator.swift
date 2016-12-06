import LLVM_C
import LLVM
import enum AST.UnaryOperator
import enum AST.BinaryOperator
import MIR

/// Generates LLVM IR code based on the MIR.
public final class IRGenerator: MIRVisitor {
    private let builder: LLVM.Builder
    private var namedValues: [String: LLVM.ValueType]
    private var returnType: Type?
    public var functionPassManager: LLVM.FunctionPassManager!
    public var module: LLVM.Module! {
        didSet { generatedFunctions.removeAll(keepingCapacity: true) }
    }
    public var arguments: [Parameter]? // Used to pass function arguments to visitor functions.
    private var generatedFunctions: [FunctionPrototype: LLVM.Function]

    public init() {
        builder = LLVM.Builder()
        namedValues = [:]
        returnType = .void // dummy initial value
        generatedFunctions = [:]
    }

    public func visit(variableDefinition: VariableDefinition) -> LLVM.ValueType {
        let value = variableDefinition.value.acceptVisitor(self)
        let alloca = builder.buildAlloca(type: value.type, name: variableDefinition.name)
        namedValues[variableDefinition.name] = alloca
        return builder.buildStore(value, to: alloca)
    }

    public func visit(variable: Variable) -> LLVM.ValueType {
        return builder.buildLoad(namedValues[variable.name]!, name: variable.name)
    }

    private func visit(unaryOperation: FunctionCall) -> LLVM.ValueType? {
        switch UnaryOperator(rawValue: unaryOperation.target.name)! {
            case .not: return buildLogicalNegation(of: unaryOperation.arguments[0])
            case .plus: return buildUnaryOperation(unaryOperation, { _ in { a, _ in a } }, { _ in { a, _ in a } })
            case .minus: return buildUnaryOperation(unaryOperation, Builder.buildNeg, Builder.buildFNeg)
        }
    }

    private func visit(binaryOperation: FunctionCall) -> LLVM.ValueType? {
        switch BinaryOperator(rawValue: binaryOperation.target.name)! {
            case .plus:
                return buildBinaryOperation(binaryOperation, Builder.buildAdd, Builder.buildFAdd, "addtmp")
            case .minus:
                return buildBinaryOperation(binaryOperation, Builder.buildSub, Builder.buildFSub, "subtmp")
            case .multiplication:
                return buildBinaryOperation(binaryOperation, Builder.buildMul, Builder.buildFMul, "multmp")
            case .division:
                return buildBinaryOperation(binaryOperation, Builder.buildSDiv, Builder.buildFDiv, "divtmp")
            case .equals:
                return buildComparisonOperation(binaryOperation, Builder.buildICmp, Builder.buildFCmp,
                                                LLVMIntEQ, LLVMRealOEQ, "eqltmp")
            case .notEquals:
                return buildComparisonOperation(binaryOperation, Builder.buildICmp, Builder.buildFCmp,
                                                LLVMIntNE, LLVMRealONE, "neqtmp")
            case .lessThan:
                return buildComparisonOperation(binaryOperation, Builder.buildICmp, Builder.buildFCmp,
                                                LLVMIntSLT, LLVMRealULT, "cmptmp")
            case .greaterThan:
                return buildComparisonOperation(binaryOperation, Builder.buildICmp, Builder.buildFCmp,
                                                LLVMIntSGT, LLVMRealUGT, "cmptmp")
            case .lessThanOrEqual:
                return buildComparisonOperation(binaryOperation, Builder.buildICmp, Builder.buildFCmp,
                                                LLVMIntSLE, LLVMRealULE, "cmptmp")
            case .greaterThanOrEqual:
                return buildComparisonOperation(binaryOperation, Builder.buildICmp, Builder.buildFCmp,
                                                LLVMIntSGE, LLVMRealUGE, "cmptmp")
        }
    }

    public func visit(functionCall: FunctionCall) -> LLVM.ValueType {
        if functionCall.isBinaryOperation {
            if let call = visit(binaryOperation: functionCall) { return call }
        } else if functionCall.isUnaryOperation {
            if let call = visit(unaryOperation: functionCall) { return call }
        }

        let argumentValues = functionCall.arguments.map { $0.acceptVisitor(self) }
        let insertBlockBackup = builder.insertBlock
        let callee = getInstantiation(of: functionCall.target)
        let name = callee.functionType.returnType != LLVM.VoidType() ? "calltmp" : ""
        builder.positionAtEnd(block: insertBlockBackup)
        return builder.buildCall(callee, args: argumentValues, name: name)
    }

    /// Returns an LLVM instantiation of the given function, instantiating a new one if needed.
    private func getInstantiation(of prototype: FunctionPrototype) -> LLVM.Function {
        if let instantiated = generatedFunctions[prototype] { return instantiated }
        return instantiateFunction(prototype)
    }

    private func instantiateFunction(_ prototype: FunctionPrototype) -> LLVM.Function {
        // Instantiate the function with the given parameter types.
        self.arguments = prototype.parameters
        if prototype.isExtern {
            return prototype.acceptVisitor(self) as! LLVM.Function
        } else {
            return prototype.body!.acceptVisitor(self) as! LLVM.Function
        }
    }

    public func visit(integerLiteral: IntegerLiteral) -> LLVM.ValueType {
        return LLVM.IntConstant.type(LLVM.IntType.int64(),
                                     value: UInt64(integerLiteral.value), signExtend: false)
    }

    public func visit(floatingPointLiteral: FloatingPointLiteral) -> LLVM.ValueType {
        return LLVM.RealConstant.type(LLVM.RealType.double(),
                                      value: floatingPointLiteral.value)
    }

    public func visit(booleanLiteral: BooleanLiteral) -> LLVM.ValueType {
        return LLVM.IntConstant.type(LLVM.IntType.int1(),
                                     value: booleanLiteral.value ? 1 : 0, signExtend: false)
    }

    public func visit(stringLiteral: StringLiteral) -> LLVM.ValueType {
        return builder.buildGlobalStringPointer(stringLiteral.value, name: "")
    }

    public func visit(nullLiteral: NullLiteral) -> LLVM.ValueType {
        fatalError("not implemented yet")
    }

    public func visit(ifStatement: IfStatement) -> LLVM.ValueType {
        // condition
        let conditionValue = ifStatement.condition.acceptVisitor(self)
        let function = builder.insertBlock.parent!
        let thenBlock = function.appendBasicBlock("then")
        let elseBlock = function.appendBasicBlock("else")
        _ = builder.buildConditionalBranch(condition: conditionValue, thenBlock: thenBlock, elseBlock: elseBlock)

        // then
        builder.positionAtEnd(block: thenBlock)
        let thenValues = ifStatement.then.map { $0.acceptVisitor(self) }
        let lastThenValue = thenValues.last as! LLVM.InstructionType?

        // else
        builder.positionAtEnd(block: elseBlock)
        let elseValues = ifStatement.else.map { $0.acceptVisitor(self) }
        let lastElseValue = elseValues.last as! LLVM.InstructionType?

        // merge
        if lastThenValue?.kind == LLVMInstructionValueKind && lastThenValue?.opCode == LLVMRet
        && lastElseValue?.kind == LLVMInstructionValueKind && lastElseValue?.opCode == LLVMRet {
            // Both branches return, no need for merge block.
            return lastThenValue! // HACK
        }

        let mergeBlock = function.appendBasicBlock("ifcont")
        builder.positionAtEnd(block: thenBlock)
        _ = builder.buildBranch(destination: mergeBlock)
        builder.positionAtEnd(block: elseBlock)
        _ = builder.buildBranch(destination: mergeBlock)
        return mergeBlock
    }

    public func visit(ifExpression: IfExpression) -> LLVM.ValueType {
        // condition
        let conditionValue = ifExpression.condition.acceptVisitor(self)
        let function = builder.insertBlock.parent!
        let thenBlock = function.appendBasicBlock("then")
        let elseBlock = function.appendBasicBlock("else")
        _ = builder.buildConditionalBranch(condition: conditionValue, thenBlock: thenBlock, elseBlock: elseBlock)

        // then
        builder.positionAtEnd(block: thenBlock)
        let thenValue = ifExpression.then.acceptVisitor(self)

        // else
        builder.positionAtEnd(block: elseBlock)
        let elseValue = ifExpression.else.acceptVisitor(self)

        // merge
        let mergeBlock = function.appendBasicBlock("ifcont")
        builder.positionAtEnd(block: thenBlock)
        _ = builder.buildBranch(destination: mergeBlock)
        builder.positionAtEnd(block: elseBlock)
        _ = builder.buildBranch(destination: mergeBlock)

        builder.positionAtEnd(block: mergeBlock)
        if thenValue.type == LLVM.VoidType() {
            return thenValue // HACK
        }
        let phi = builder.buildPhi(thenValue.type, name: "iftmp")
        phi.addIncoming(thenValue, from: thenBlock)
        phi.addIncoming(elseValue, from: elseBlock)
        return phi
    }

    public func visit(function: MIR.Function) -> LLVM.ValueType {
        let llvmFunction = function.prototype.acceptVisitor(self) as! LLVM.Function
        let basicBlock = llvmFunction.appendBasicBlock("entry")
        builder.positionAtEnd(block: basicBlock)
        let namedValuesBackup = namedValues
        namedValues.removeAll(keepingCapacity: true)
        createParameterAllocas(function.prototype, llvmFunction)
        let body = function.body.map { $0.acceptVisitor(self) }
        namedValues = namedValuesBackup

        if let instruction = body.last as? LLVM.InstructionType, instruction.opCode == LLVMRet {
        } else {
            builder.positionAtEnd(block: llvmFunction.basicBlocks.last!)
            _ = builder.buildReturnVoid()
        }
        precondition(llvmFunction.verify(failureAction: LLVMPrintMessageAction))
        functionPassManager.run(on: llvmFunction)
        return llvmFunction
    }

    public func visit(prototype: FunctionPrototype) -> LLVM.ValueType {
        let actualParameterTypes = arguments!.map { $0.type.llvmType }

        if let declaredReturnType = prototype.returnType {
            returnType = declaredReturnType
        }
        let functionType = LLVM.FunctionType(returnType: returnType!.llvmType,
                                             paramTypes: actualParameterTypes, isVarArg: false)
        let function = LLVM.Function(name: prototype.name, type: functionType, inModule: module)
        let parameterValues = function.params

        for (var parameter, name) in zip(parameterValues, prototype.parameters.map { $0.name }) {
            parameter.name = name
        }

        generatedFunctions[prototype] = function
        return function
    }

    public func visit(returnStatement: ReturnStatement) -> LLVM.ValueType {
        guard let expression = returnStatement.value else { return builder.buildReturnVoid() }
        let value = expression.acceptVisitor(self)
        if value.type != LLVM.VoidType() { return builder.buildReturn(value: value) }
        return builder.buildReturnVoid() // TODO: don't allow returning void expressions
    }

    private func createParameterAllocas(_ prototype: FunctionPrototype, _ function: LLVM.Function) {
        for (parameter, parameterValue) in zip(prototype.parameters, function.params) {
            let alloca = createEntryBlockAlloca(for: function, name: parameter.name, type: parameterValue.type)
            _ = builder.buildStore(parameterValue, to: alloca)
            namedValues[parameter.name] = alloca
        }
    }

    typealias UnaryOperationBuildFunc =
        (LLVM.Builder) -> (LLVM.ValueType, String) -> LLVM.ValueType!

    private func buildUnaryOperation(_ operation: FunctionCall,
                                     _ integerOperationBuildFunc: UnaryOperationBuildFunc,
                                     _ floatingPointOperationBuildFunc: UnaryOperationBuildFunc) -> LLVM.ValueType? {
        let operand = operation.arguments[0].acceptVisitor(self)

        switch operand.type {
            case LLVM.IntType.int64(): return integerOperationBuildFunc(builder)(operand, "negtmp")
            case LLVM.RealType.double(): return floatingPointOperationBuildFunc(builder)(operand, "negtmp")
            default: break
        }

        return nil
    }

    private func buildLogicalNegation(of expression: Expression) -> LLVM.ValueType {
        let operand = expression.acceptVisitor(self)
        let falseConstant = LLVM.IntConstant.type(LLVM.IntType.int1(), value: 0, signExtend: false)
        return builder.buildICmp(LLVMIntEQ, left: operand, right: falseConstant, name: "negtmp")
    }

    typealias IntComparisonOperationBuildFunc =
        (LLVM.Builder) -> (LLVMIntPredicate, LLVM.ValueType, LLVM.ValueType, String) -> LLVM.ValueType!
    typealias RealComparisonOperationBuildFunc =
        (LLVM.Builder) -> (LLVMRealPredicate, LLVM.ValueType, LLVM.ValueType, String) -> LLVM.ValueType!

    private func buildComparisonOperation(_ operation: FunctionCall,
                                          _ integerOperationBuildFunc: IntComparisonOperationBuildFunc,
                                          _ floatingPointOperationBuildFunc: RealComparisonOperationBuildFunc,
                                          _ integerOperationPredicate: LLVMIntPredicate,
                                          _ floatingPointOperationPredicate: LLVMRealPredicate,
                                          _ name: String) -> LLVM.ValueType? {
        var lhs = operation.arguments[0].acceptVisitor(self)
        var rhs = operation.arguments[1].acceptVisitor(self)

        // Interpret integer literals as floating-point in contexts that require a floating-point operand.
        if lhs.type == LLVM.RealType.double() && operation.arguments[1] as? IntegerLiteral != nil {
            rhs = AnyValue(ref: LLVMConstSIToFP(rhs.ref, LLVM.RealType.double().ref))
        } else if rhs.type == LLVM.RealType.double() && operation.arguments[0] as? IntegerLiteral != nil {
            lhs = AnyValue(ref: LLVMConstSIToFP(lhs.ref, LLVM.RealType.double().ref))
        }

        switch (lhs.type, rhs.type) {
            case (LLVM.IntType.int1(), LLVM.IntType.int1()),
                 (LLVM.IntType.int64(), LLVM.IntType.int64()):
                return integerOperationBuildFunc(builder)(integerOperationPredicate, lhs, rhs, name)
            case (LLVM.RealType.double(), LLVM.RealType.double()):
                return floatingPointOperationBuildFunc(builder)(floatingPointOperationPredicate, lhs, rhs, name)
            default: break
        }
        return nil
    }

    typealias BinaryOperationBuildFunc =
        (LLVM.Builder) -> (LLVM.ValueType, LLVM.ValueType, String) -> LLVM.ValueType!

    private func buildBinaryOperation(_ operation: FunctionCall,
                                      _ integerOperationBuildFunc: BinaryOperationBuildFunc,
                                      _ floatingPointOperationBuildFunc: BinaryOperationBuildFunc,
                                      _ name: String) -> LLVM.ValueType? {
        let lhs = operation.arguments[0].acceptVisitor(self)
        let rhs = operation.arguments[1].acceptVisitor(self)

        switch (lhs.type, rhs.type) {
            case (LLVM.IntType.int64(), LLVM.IntType.int64()):
                return integerOperationBuildFunc(builder)(lhs, rhs, name)
            case (LLVM.RealType.double(), LLVM.RealType.double()):
                return floatingPointOperationBuildFunc(builder)(lhs, rhs, name)
            default: break
        }

        return nil
    }

    private func createEntryBlockAlloca(for function: LLVM.Function, name: String, type: LLVM.TypeType) -> LLVM.AllocaInstruction {
        let temporaryBuilder = Builder()
        temporaryBuilder.position(block: function.entry, instruction: function.entry.firstInstruction)
        return builder.buildAlloca(type: type, name: name)
    }

    public func appendToMainFunction(_ statement: Statement) {
        builder.positionAtEnd(block: getMainFunction().basicBlocks.last!)
        _ = statement.acceptVisitor(self)
    }

    /// Creates a `return 0` statement at the end of `main` if it doesn't already have a return statement.
    public func appendImplicitZeroReturnToMainFunction() {
        if let instruction = getMainFunction().basicBlocks.last?.lastInstruction, instruction.opCode == LLVMRet {
            return
        }
        builder.positionAtEnd(block: getMainFunction().basicBlocks.last!)
        _ = builder.buildReturn(value: LLVM.IntConstant.type(LLVM.IntType.int64(), value: 0, signExtend: false))
    }

    private func getMainFunction() -> LLVM.Function {
        if let mainFunction = module.functionByName("main") { return mainFunction }

        // Create main function if it doesn't exist.
        let mainFunctionType = LLVM.FunctionType(returnType: LLVM.IntType.int64(), paramTypes: [], isVarArg: false)
        let mainFunction = LLVM.Function(name: "main", type: mainFunctionType, inModule: module)
        _ = mainFunction.appendBasicBlock("entry")
        return mainFunction
    }
}
