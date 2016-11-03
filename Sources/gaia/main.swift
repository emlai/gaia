import LLVM_C.Analysis
import LLVM_C.Core

let module = LLVMModuleCreateWithName("gaia")
LLVMDumpModule(module)
LLVMDisposeModule(module)
