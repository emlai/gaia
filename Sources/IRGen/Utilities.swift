import LLVM_C
import LLVM
import AST

public enum CompileError: SourceCodeError {
    case invalidType(location: SourceLocation, message: String)
    case unknownIdentifier(location: SourceLocation, message: String)
    case argumentMismatch(message: String)
    case redefinition(location: SourceLocation, message: String)

    public var location: SourceLocation? {
        switch self {
            case .invalidType(let location, _), .unknownIdentifier(let location, _),
                 .redefinition(let location, _):
                return location
            case .argumentMismatch:
                return nil
        }
    }

    public var description: String {
        switch self {
            case .invalidType(_, let message), .unknownIdentifier(_, let message),
                 .redefinition(_, let message), .argumentMismatch(let message):
                return message
        }
    }
}

extension FunctionCall {
    convenience init(from binaryOperation: BinaryOperation) throws {
        self.init(functionName: binaryOperation.operator.rawValue,
                  arguments: [binaryOperation.leftOperand, binaryOperation.rightOperand],
                  at: binaryOperation.sourceLocation)
    }

    convenience init(from unaryOperation: UnaryOperation) throws {
        self.init(functionName: unaryOperation.operator.rawValue,
                  arguments: [unaryOperation.operand],
                  at: unaryOperation.sourceLocation)
    }
}

public struct Argument {
    let type: LLVM.TypeType
    let sourceLocation: SourceLocation
}

extension LLVM.TypeType {
    /// The Gaia type name corresponding to the LLVM type of this value.
    var gaiaTypeName: String {
        switch self {
            case LLVM.VoidType(): return "Void"
            case LLVM.IntType.int1(): return "Bool"
            case LLVM.IntType.int8(): return "Int8"
            case LLVM.IntType.int16(): return "Int16"
            case LLVM.IntType.int32(): return "Int32"
            case LLVM.IntType.int64(): return "Int"
            case LLVM.RealType.float(): return "Float32"
            case LLVM.RealType.double(): return "Float"
            default:
                if self.kind == LLVMPointerTypeKind
                && LLVMGetElementType(self.ref) == LLVM.IntType.int8().ref {
                    return "String"
                }
                fatalError("unsupported type `\(self.string)`")
        }
    }
}

func llvmTypeFromGaiaTypeName(_ gaiaTypeName: String) -> LLVM.TypeType? {
    switch gaiaTypeName {
        case "Void": return LLVM.VoidType()
        case "Bool": return LLVM.IntType.int1()
        case "Int8": return LLVM.IntType.int8()
        case "Int16": return LLVM.IntType.int16()
        case "Int32": return LLVM.IntType.int32()
        case "Int64", "Int": return LLVM.IntType.int64()
        case "Float32": return LLVM.RealType.float()
        case "Float64", "Float": return LLVM.RealType.double()
        case "String": return LLVM.PointerType(type: LLVM.IntType.int8(), addressSpace: 0)
        default: return nil
    }
}
