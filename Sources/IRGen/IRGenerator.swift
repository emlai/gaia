import LLVM_C
import LLVM
import AST

/// Generates LLVM IR code based on the abstract syntax tree.
public final class IRGenerator: ASTVisitor {
    private let builder: LLVM.Builder
    private var namedValues: [String: LLVM.ValueType]
    private var functionDefinitions: [String: AST.Function]
    private var externFunctionPrototypes: [String: FunctionPrototype]
    private var returnType: Type?
    public var functionPassManager: LLVM.FunctionPassManager!
    public var module: LLVM.Module!
    public var arguments: [Argument]? // Used to pass function arguments to visitor functions.

    public init() {
        builder = LLVM.Builder()
        namedValues = [:]
        functionDefinitions = [:]
        externFunctionPrototypes = [:]
        returnType = .void // dummy initial value
    }

    public func visit(variableDefinition: VariableDefinition) throws -> LLVM.ValueType {
        let value = try variableDefinition.value.acceptVisitor(self)
        let alloca = builder.buildAlloca(type: value.type, name: variableDefinition.name)
        namedValues[variableDefinition.name] = alloca
        return builder.buildStore(value, to: alloca)
    }

    public func visit(variable: Variable) throws -> LLVM.ValueType {
        return builder.buildLoad(namedValues[variable.name]!, name: variable.name)
    }

    public func visit(unaryOperation: UnaryOperation) throws -> LLVM.ValueType {
        switch unaryOperation.operator {
            case .not: return try buildLogicalNegation(of: unaryOperation.operand)
            case .plus: return try buildUnaryOperation(unaryOperation, { _ in { a, _ in a } }, { _ in { a, _ in a } })
            case .minus: return try buildUnaryOperation(unaryOperation, Builder.buildNeg, Builder.buildFNeg)
        }
    }

    public func visit(binaryOperation: BinaryOperation) throws -> LLVM.ValueType {
        switch binaryOperation.operator {
            case .plus: return try buildBinaryOperation(binaryOperation, Builder.buildAdd, Builder.buildFAdd, "addtmp")
            case .minus: return try buildBinaryOperation(binaryOperation, Builder.buildSub, Builder.buildFSub, "subtmp")
            case .multiplication: return try buildBinaryOperation(binaryOperation, Builder.buildMul, Builder.buildFMul, "multmp")
            case .division: return try buildBinaryOperation(binaryOperation, Builder.buildSDiv, Builder.buildFDiv, "divtmp")
            case .equals: return try buildComparisonOperation(binaryOperation, Builder.buildICmp, Builder.buildFCmp, LLVMIntEQ, LLVMRealOEQ, "eqltmp")
            case .notEquals:
                let temporaryOperation = BinaryOperation(operator: .equals,
                                                         leftOperand: binaryOperation.leftOperand,
                                                         rightOperand: binaryOperation.rightOperand,
                                                         at: binaryOperation.sourceLocation)
                return try buildLogicalNegation(of: temporaryOperation)
            case .lessThan: return try buildComparisonOperation(binaryOperation, Builder.buildICmp, Builder.buildFCmp, LLVMIntSLT, LLVMRealULT, "cmptmp")
            case .greaterThan:
                let temporaryOperation = BinaryOperation(operator: .lessThan,
                                                         leftOperand: binaryOperation.rightOperand,
                                                         rightOperand: binaryOperation.leftOperand,
                                                         at: binaryOperation.sourceLocation)
                return try temporaryOperation.acceptVisitor(self)
            case .lessThanOrEqual:
                let temporaryOperation = BinaryOperation(operator: .lessThan,
                                                         leftOperand: binaryOperation.rightOperand,
                                                         rightOperand: binaryOperation.leftOperand,
                                                         at: binaryOperation.sourceLocation)
                return try buildLogicalNegation(of: temporaryOperation)
            case .greaterThanOrEqual:
                let temporaryOperation = BinaryOperation(operator: .lessThan,
                                                         leftOperand: binaryOperation.leftOperand,
                                                         rightOperand: binaryOperation.rightOperand,
                                                         at: binaryOperation.sourceLocation)
                return try buildLogicalNegation(of: temporaryOperation)
        }
    }

    public func visit(functionCall: FunctionCall) throws -> LLVM.ValueType {
        let prototype: FunctionPrototype
        let nonExternFunction: AST.Function?
        if let externPrototype = externFunctionPrototypes[functionCall.functionName] {
            prototype = externPrototype
            nonExternFunction = nil
        } else if let function = functionDefinitions[functionCall.functionName] {
            prototype = function.prototype
            nonExternFunction = function
        } else {
            fatalError("unknown function name '\(functionCall.functionName)'")
        }

        var argumentValues = [ValueType]()
        argumentValues.reserveCapacity(functionCall.arguments.count)
        for argument in functionCall.arguments {
            argumentValues.append(try argument.acceptVisitor(self))
        }

        let insertBlockBackup = builder.insertBlock
        self.arguments = zip(argumentValues, functionCall.arguments).map {
            Argument(type: $0.0.type, sourceLocation: $0.1.sourceLocation)
        }

        let callee: LLVM.Function
        self.returnType = functionCall.returnType!
        if let function = nonExternFunction {
            callee = try getInstantiation(of: function, for: arguments!)
        } else {
            callee = try module.functionByName(functionCall.functionName) ?? prototype.acceptVisitor(self) as! LLVM.Function
        }

        let name = callee.functionType.returnType != LLVM.VoidType() ? "calltmp" : ""
        builder.positionAtEnd(block: insertBlockBackup)
        return builder.buildCall(callee, args: argumentValues, name: name)
    }

    /// Returns an instantiation of the given function for the given parameter types,
    /// building a new concrete function if it has not yet been instantiated.
    /// Returns `nil` if the function cannot be instantiated for the given parameter types,
    /// e.g. because of conflicting parameter type constraints.
    private func getInstantiation(of function: AST.Function, for arguments: [Argument]) throws -> LLVM.Function {
        if let generated = module.functionByName(function.prototype.name) {
            if generated.functionType.paramTypes == arguments.map({ $0.type }) {
                return generated
            }
        }
        // Instantiate the function with the given parameter types.
        self.arguments = arguments
        return try function.acceptVisitor(self) as! LLVM.Function
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

    public func visit(ifStatement: IfStatement) throws -> LLVM.ValueType {
        // condition
        let conditionValue = try ifStatement.condition.acceptVisitor(self)
        let function = builder.insertBlock.parent!
        let thenBlock = function.appendBasicBlock("then")
        let elseBlock = function.appendBasicBlock("else")
        _ = builder.buildConditionalBranch(condition: conditionValue, thenBlock: thenBlock, elseBlock: elseBlock)
        
        // then
        builder.positionAtEnd(block: thenBlock)
        let thenValues = try ifStatement.then.map { try $0.acceptVisitor(self) }
        let lastThenValue = thenValues.last as! LLVM.InstructionType?

        // else
        builder.positionAtEnd(block: elseBlock)
        let elseValues = try ifStatement.else.map { try $0.acceptVisitor(self) }
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

    public func visit(ifExpression: IfExpression) throws -> LLVM.ValueType {
        // condition
        let conditionValue = try ifExpression.condition.acceptVisitor(self)
        let function = builder.insertBlock.parent!
        let thenBlock = function.appendBasicBlock("then")
        let elseBlock = function.appendBasicBlock("else")
        _ = builder.buildConditionalBranch(condition: conditionValue, thenBlock: thenBlock, elseBlock: elseBlock)

        // then
        builder.positionAtEnd(block: thenBlock)
        let thenValue = try ifExpression.then.acceptVisitor(self)

        // else
        builder.positionAtEnd(block: elseBlock)
        let elseValue = try ifExpression.else.acceptVisitor(self)

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

    public func visit(function: AST.Function) throws -> LLVM.ValueType {
        let arguments = self.arguments!
        let (llvmFunction, body) = try buildFunctionBody(of: function, arguments: arguments)

        if let instruction = body.last as? LLVM.InstructionType, instruction.opCode == LLVMRet {
        } else {
            builder.positionAtEnd(block: llvmFunction.basicBlocks.last!)
            _ = builder.buildReturnVoid()
        }
        precondition(llvmFunction.verify(failureAction: LLVMPrintMessageAction))
        functionPassManager.run(on: llvmFunction)
        return llvmFunction
    }

    public func visit(prototype: FunctionPrototype) throws -> LLVM.ValueType {
        let actualParameterTypes = arguments!.map { $0.type }

        if let declaredReturnType = prototype.returnType {
            returnType = Type(rawValue: declaredReturnType)! // TODO: error handling
        }
        let functionType = LLVM.FunctionType(returnType: returnType!.llvmType,
                                             paramTypes: actualParameterTypes, isVarArg: false)
        let function = LLVM.Function(name: prototype.name, type: functionType, inModule: module)
        let parameterValues = function.params

        for (var parameter, name) in zip(parameterValues, prototype.parameters.map { $0.name }) {
            parameter.name = name
        }

        return function
    }

    public func visit(returnStatement: ReturnStatement) throws -> LLVM.ValueType {
        guard let expression = returnStatement.value else { return builder.buildReturnVoid() }
        let value = try expression.acceptVisitor(self)
        if value.type != LLVM.VoidType() { return builder.buildReturn(value: value) }
        return builder.buildReturnVoid() // TODO: don't allow returning void expressions
    }

    public func registerFunctionDefinition(_ function: AST.Function) {
        functionDefinitions[function.prototype.name] = function
    }

    public func registerExternFunctionDeclaration(_ prototype: FunctionPrototype) {
        externFunctionPrototypes[prototype.name] = prototype
    }

    /// Searches `module` for an existing function declaration with the given name,
    /// or, if it doesn't find one, generates a new one from `functionDefinitions`.
    func lookupFunction(named functionName: String, arguments: [Argument]) throws -> LLVM.Function? {
        // First, see if the function has already been added to the current module.
        if let function = module.functionByName(functionName) {
            if function.functionType.paramTypes == arguments.map({ $0.type }) {
                return function
            }
        }

        // If not, check whether we can codegen the declaration from some existing prototype.
        if let astFunction = functionDefinitions[functionName] {
            self.arguments = arguments
            let function = try astFunction.prototype.acceptVisitor(self)
            return Optional.some(function as! LLVM.Function)
        }

        return nil // No existing prototype exists.
    }

    private func createParameterAllocas(_ prototype: FunctionPrototype, _ function: LLVM.Function) {
        for (parameter, parameterValue) in zip(prototype.parameters, function.params) {
            let alloca = createEntryBlockAlloca(for: function, name: parameter.name, type: parameterValue.type)
            _ = builder.buildStore(parameterValue, to: alloca)
            namedValues[parameter.name] = alloca
        }
    }

    private func buildFunctionBody(of astFunction: AST.Function, arguments: [Argument]) throws
    -> (function: LLVM.Function, body: [LLVM.ValueType]) {
        let llvmFunction = try lookupFunction(named: astFunction.prototype.name, arguments: arguments)!
        let basicBlock = llvmFunction.appendBasicBlock("entry")
        builder.positionAtEnd(block: basicBlock)
        let namedValuesBackup = namedValues
        namedValues.removeAll(keepingCapacity: true)
        createParameterAllocas(astFunction.prototype, llvmFunction)
        do {
            let body = try astFunction.body.map { try $0.acceptVisitor(self) }
            namedValues = namedValuesBackup
            return (llvmFunction, body)
        } catch {
            // Error reading body, remove function.
            llvmFunction.delete()
            throw error
        }
    }

    typealias UnaryOperationBuildFunc =
        (LLVM.Builder) -> (LLVM.ValueType, String) -> LLVM.ValueType!

    private func buildUnaryOperation(_ operation: UnaryOperation,
                                     _ integerOperationBuildFunc: UnaryOperationBuildFunc,
                                     _ floatingPointOperationBuildFunc: UnaryOperationBuildFunc) throws -> LLVM.ValueType {
        let operand = try operation.operand.acceptVisitor(self)

        switch operand.type {
            case LLVM.IntType.int64(): return integerOperationBuildFunc(builder)(operand, "negtmp")
            case LLVM.RealType.double(): return floatingPointOperationBuildFunc(builder)(operand, "negtmp")
            default: break
        }

        // It wasn't a built-in operator. Check if it's a user-defined one.
        return try FunctionCall(from: operation).acceptVisitor(self)
    }

    private func buildLogicalNegation(of expression: Expression) throws -> LLVM.ValueType {
        let operand = try expression.acceptVisitor(self)
        let falseConstant = LLVM.IntConstant.type(LLVM.IntType.int1(), value: 0, signExtend: false)
        return builder.buildICmp(LLVMIntEQ, left: operand, right: falseConstant, name: "negtmp")
    }

    typealias IntComparisonOperationBuildFunc =
        (LLVM.Builder) -> (LLVMIntPredicate, LLVM.ValueType, LLVM.ValueType, String) -> LLVM.ValueType!
    typealias RealComparisonOperationBuildFunc =
        (LLVM.Builder) -> (LLVMRealPredicate, LLVM.ValueType, LLVM.ValueType, String) -> LLVM.ValueType!

    private func buildComparisonOperation(_ operation: BinaryOperation,
                                          _ integerOperationBuildFunc: IntComparisonOperationBuildFunc,
                                          _ floatingPointOperationBuildFunc: RealComparisonOperationBuildFunc,
                                          _ integerOperationPredicate: LLVMIntPredicate,
                                          _ floatingPointOperationPredicate: LLVMRealPredicate,
                                          _ name: String) throws -> LLVM.ValueType {
        var lhs = try operation.leftOperand.acceptVisitor(self)
        var rhs = try operation.rightOperand.acceptVisitor(self)

        // Interpret integer literals as floating-point in contexts that require a floating-point operand.
        if lhs.type == LLVM.RealType.double() && operation.rightOperand as? IntegerLiteral != nil {
            rhs = AnyValue(ref: LLVMConstSIToFP(rhs.ref, LLVM.RealType.double().ref))
        } else if rhs.type == LLVM.RealType.double() && operation.leftOperand as? IntegerLiteral != nil {
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

        // It wasn't a built-in operator. Check if it's a user-defined one.
        return try FunctionCall(from: operation).acceptVisitor(self)
    }

    typealias BinaryOperationBuildFunc =
        (LLVM.Builder) -> (LLVM.ValueType, LLVM.ValueType, String) -> LLVM.ValueType!

    private func buildBinaryOperation(_ operation: BinaryOperation,
                                      _ integerOperationBuildFunc: BinaryOperationBuildFunc,
                                      _ floatingPointOperationBuildFunc: BinaryOperationBuildFunc,
                                      _ name: String) throws -> LLVM.ValueType {
        let lhs = try operation.leftOperand.acceptVisitor(self)
        let rhs = try operation.rightOperand.acceptVisitor(self)

        switch (lhs.type, rhs.type) {
            case (LLVM.IntType.int64(), LLVM.IntType.int64()):
                return integerOperationBuildFunc(builder)(lhs, rhs, name)
            case (LLVM.RealType.double(), LLVM.RealType.double()):
                return floatingPointOperationBuildFunc(builder)(lhs, rhs, name)
            default: break
        }

        // It wasn't a built-in operator. Check if it's a user-defined one.
        return try FunctionCall(from: operation).acceptVisitor(self)
    }

    private func createEntryBlockAlloca(for function: LLVM.Function, name: String, type: LLVM.TypeType) -> LLVM.AllocaInstruction {
        let temporaryBuilder = Builder()
        temporaryBuilder.position(block: function.entry, instruction: function.entry.firstInstruction)
        return builder.buildAlloca(type: type, name: name)
    }

    public func appendToMainFunction(_ statement: Statement) throws {
        builder.positionAtEnd(block: getMainFunction().basicBlocks.last!)
        _ = try statement.acceptVisitor(self)
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
