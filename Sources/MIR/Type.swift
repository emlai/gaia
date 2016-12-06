import LLVM

public indirect enum Type: Equatable, CustomStringConvertible {
    case void
    case int8
    case int16
    case int32
    case int64
    case int
    case bool
    case float32
    case float64
    case float
    case string
    case pointer(to: Type)
    case typeOfNull

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
            case .pointer(to: let type): return LLVM.PointerType(type: type.llvmType, addressSpace: 0)
            case .typeOfNull: fatalError("typeOfNull has no LLVM equivalent")
        }
    }

    public static func ==(lhs: Type, rhs: Type) -> Bool {
        return lhs.description == rhs.description
    }
    
    public init?(_ description: String) {
        switch description {
            case "Void": self = .void
            case "Int8": self = .int8
            case "Int16": self = .int16
            case "Int32": self = .int32
            case "Int64": self = .int64
            case "Int": self = .int
            case "Bool": self = .bool
            case "Float32": self = .float32
            case "Float64": self = .float64
            case "Float": self = .float
            case "String": self = .string
            case "Null": self = .typeOfNull
            default:
                if description.characters.last == "*" {
                    if let pointedToType = Type(String(description.characters.dropLast())) {
                        self = .pointer(to: pointedToType); return
                    }
                }
                return nil
        }
    }

    public var description: String {
        switch self {
            case .void: return "Void"
            case .int8: return "Int8"
            case .int16: return "Int16"
            case .int32: return "Int32"
            case .int64: return "Int64"
            case .int: return "Int"
            case .bool: return "Bool"
            case .float32: return "Float32"
            case .float64: return "Float64"
            case .float: return "Float"
            case .string: return "String"
            case .pointer(to: let type): return type.description + "*"
            case .typeOfNull: return "Null"
        }
    }
}
