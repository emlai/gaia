import LLVM

public enum Type: String, Hashable, CustomStringConvertible {
    case void = "Void"
    case int8 = "Int8"
    case int16 = "Int16"
    case int32 = "Int32"
    case int64 = "Int64"
    case int = "Int"
    case bool = "Bool"
    case float32 = "Float32"
    case float64 = "Float64"
    case float = "Float"
    case string = "String"
    case typeOfNull = "Null"

    public var llvmType: LLVM.TypeType {
        switch self {
            case .void: return LLVM.VoidType()
            case .bool: return LLVM.IntType.int1()
            case .int8: return LLVM.IntType.int8()
            case .int16: return LLVM.IntType.int16()
            case .int32: return LLVM.IntType.int32()
            case .int64, .int: return LLVM.IntType.int64()
            case .float32: return LLVM.RealType.float()
            case .float64, .float: return LLVM.RealType.double()
            case .string: return LLVM.PointerType(type: LLVM.IntType.int8(), addressSpace: 0)
            case .typeOfNull: fatalError("typeOfNull has no LLVM equivalent")
        }
    }

    public var description: String { return rawValue }
}
