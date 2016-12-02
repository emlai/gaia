import LLVM_C
import LLVM
import AST

extension FunctionCall {
    convenience init(from binaryOperation: BinaryOperation) throws {
        self.init(functionName: binaryOperation.operator.rawValue,
                  arguments: [binaryOperation.leftOperand, binaryOperation.rightOperand],
                  at: binaryOperation.sourceLocation)
        self.returnType = binaryOperation.returnType
    }

    convenience init(from unaryOperation: UnaryOperation) throws {
        self.init(functionName: unaryOperation.operator.rawValue,
                  arguments: [unaryOperation.operand],
                  at: unaryOperation.sourceLocation)
        self.returnType = unaryOperation.returnType
    }
}

public struct Argument {
    let type: LLVM.TypeType
    let sourceLocation: SourceLocation
}
