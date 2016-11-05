#ifndef GAIA_JIT_H
#define GAIA_JIT_H

#include <llvm-c/TargetMachine.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct GaiaOpaqueJIT* GaiaJITRef;
typedef struct GaiaOpaqueJITModuleHandle* GaiaJITModuleHandle;

GaiaJITRef GaiaCreateJIT();
void GaiaDisposeJIT(GaiaJITRef jit);
LLVMTargetMachineRef GaiaGetJITTargetMachine(GaiaJITRef jit);
GaiaJITModuleHandle GaiaJITAddModule(GaiaJITRef jit, LLVMModuleRef* module);
void GaiaJITRemoveModule(GaiaJITRef jit, GaiaJITModuleHandle moduleHandle);
void GaiaJITDisposeModuleHandle(GaiaJITModuleHandle);
void* GaiaJITFindSymbolAddress(GaiaJITRef jit, const char* name);

#ifdef __cplusplus
} // extern "C"
#endif

#endif
