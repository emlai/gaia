import LLVM_C.Core
import AST

public enum IRGenError: SourceCodeError {
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

let LLVMFalse: LLVMBool = 0
let LLVMTrue: LLVMBool = 1

public struct Argument {
    let type: LLVMTypeRef
    let sourceLocation: SourceLocation
}

/// Convenience wrapper around `LLVMGetParams` that returns the parameter array.
func LLVMGetParams(_ function: LLVMValueRef) -> [LLVMValueRef] {
    var parameters = ContiguousArray<LLVMValueRef?>(repeating: nil, count: Int(LLVMCountParams(function)))
    parameters.withUnsafeMutableBufferPointer { LLVMGetParams(function, $0.baseAddress) }
    return parameters.map { $0! }
}

/// Convenience wrapper around `LLVMGetParamTypes` that returns the parameter type array.
func LLVMGetParamTypes(_ functionType: LLVMTypeRef) -> [LLVMTypeRef] {
    var parameters = ContiguousArray<LLVMTypeRef?>(repeating: nil, count: Int(LLVMCountParamTypes(functionType)))
    parameters.withUnsafeMutableBufferPointer { LLVMGetParamTypes(functionType, $0.baseAddress) }
    return parameters.map { $0! }
}

extension LLVMValueRef {
    var returnType: LLVMTypeRef {
        return LLVMGetReturnType(LLVMGetElementType(LLVMTypeOf(self)))
    }
}

extension LLVMTypeRef {
    /// The Gaia type name corresponding to the LLVM type of this value.
    var gaiaTypeName: String {
        switch self {
            case LLVMVoidType(): return "Void"
            case LLVMInt1Type(): return "Bool"
            case LLVMInt8Type(): return "Int8"
            case LLVMInt16Type(): return "Int16"
            case LLVMInt32Type(): return "Int32"
            case LLVMInt64Type(): return "Int"
            case LLVMFloatType(): return "Float32"
            case LLVMDoubleType(): return "Float"
            default:
                if LLVMGetTypeKind(self) == LLVMPointerTypeKind
                && LLVMGetElementType(self) == LLVMInt8Type() {
                    return "String"
                }

                let typeName = LLVMPrintTypeToString(self)
                defer { LLVMDisposeMessage(typeName) }
                fatalError("unsupported type `\(String(cString: typeName!))`")
        }
    }
}

extension LLVMTypeRef {
    init?(gaiaTypeName: String) {
        switch gaiaTypeName {
            case "Void": self = LLVMVoidType()
            case "Bool": self = LLVMInt1Type()
            case "Int8": self = LLVMInt8Type()
            case "Int16": self = LLVMInt16Type()
            case "Int32": self = LLVMInt32Type()
            case "Int64", "Int": self = LLVMInt64Type()
            case "Float32": self = LLVMFloatType()
            case "Float64", "Float": self = LLVMDoubleType()
            case "String": self = LLVMPointerType(LLVMInt8Type(), 0)
            default: return nil
        }
    }
}
