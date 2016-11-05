#include <memory>
#include <vector>
#include <string>
#include <llvm/ExecutionEngine/OrcMCJITReplacement.h>
#include <llvm/ExecutionEngine/Orc/ObjectLinkingLayer.h>
#include <llvm/ExecutionEngine/Orc/IRCompileLayer.h>
#include <llvm/ExecutionEngine/ExecutionEngine.h>
#include <llvm/ExecutionEngine/RTDyldMemoryManager.h>
#include <llvm/ExecutionEngine/Orc/CompileUtils.h>
#include <llvm/ExecutionEngine/Orc/LambdaResolver.h>
#include <llvm/IR/Mangler.h>
#include <llvm/Support/DynamicLibrary.h>
#include "JIT.h"

namespace gaia {

/// A simple JIT, based on
/// https://llvm.org/svn/llvm-project/llvm/trunk/examples/Kaleidoscope/include/KaleidoscopeJIT.h
class JIT {
public:
    using ObjectLayer = llvm::orc::ObjectLinkingLayer<>;
    using CompileLayer = llvm::orc::IRCompileLayer<ObjectLayer>;
    using ModuleHandle = CompileLayer::ModuleSetHandleT;

public:
    JIT();
    llvm::TargetMachine& getTargetMachine() { return *targetMachine; }
    ModuleHandle addModule(std::unique_ptr<llvm::Module>);
    void removeModule(ModuleHandle);
    llvm::orc::JITSymbol findSymbol(llvm::StringRef name);

private:
    std::string mangle(llvm::StringRef name);
    llvm::orc::JITSymbol findMangledSymbol(llvm::StringRef name);

private:
    std::unique_ptr<llvm::TargetMachine> targetMachine;
    llvm::DataLayout const dataLayout;
    ObjectLayer objectLayer;
    CompileLayer compileLayer;
    std::vector<ModuleHandle> moduleHandles;
};

JIT::JIT()
: targetMachine(llvm::EngineBuilder().selectTarget()),
  dataLayout(targetMachine->createDataLayout()),
  compileLayer(objectLayer, llvm::orc::SimpleCompiler(*targetMachine)) {
    llvm::sys::DynamicLibrary::LoadLibraryPermanently(nullptr);
}

JIT::ModuleHandle JIT::addModule(std::unique_ptr<llvm::Module> module) {
    // We need a memory manager to allocate memory and resolve symbols for this
    // new module. Create one that resolves symbols by looking back into the JIT.
    auto resolver = llvm::orc::createLambdaResolver(
        [&](std::string const& name) {
            if (auto symbol = findMangledSymbol(name)) {
                return llvm::RuntimeDyld::SymbolInfo(symbol.getAddress(), symbol.getFlags());
            }
            return llvm::RuntimeDyld::SymbolInfo(nullptr);
        },
        [](std::string const&) { return nullptr; });

    std::vector<std::unique_ptr<llvm::Module>> moduleSet;
    moduleSet.push_back(std::move(module));

    auto moduleHandle = compileLayer.addModuleSet(std::move(moduleSet),
                                                  llvm::make_unique<llvm::SectionMemoryManager>(),
                                                  std::move(resolver));
    moduleHandles.push_back(moduleHandle);
    return moduleHandle;
}

void JIT::removeModule(ModuleHandle moduleHandle) {
    moduleHandles.erase(std::find(moduleHandles.begin(), moduleHandles.end(), moduleHandle));
    compileLayer.removeModuleSet(moduleHandle);
}

llvm::orc::JITSymbol JIT::findSymbol(llvm::StringRef name) {
    return findMangledSymbol(mangle(name));
}

std::string JIT::mangle(llvm::StringRef name) {
    std::string mangledName;
    {
        llvm::raw_string_ostream mangledNameStream(mangledName);
        llvm::Mangler::getNameWithPrefix(mangledNameStream, name, dataLayout);
    }
    return mangledName;
}

llvm::orc::JITSymbol JIT::findMangledSymbol(llvm::StringRef name) {
    // Search modules in reverse order: from last added to first added.
    // This is the opposite of the usual search order for dlsym, but makes more
    // sense in a REPL where we want to bind to the newest available definition.
    for (auto handle : llvm::make_range(moduleHandles.rbegin(), moduleHandles.rend())) {
        if (auto symbol = compileLayer.findSymbolIn(handle, name, true)) {
            return symbol;
        }
    }

    // If we can't find the symbol in the JIT, try looking in the host process.
    if (auto symbolAddress = llvm::RTDyldMemoryManager::getSymbolAddressInProcess(name)) {
        return llvm::orc::JITSymbol(symbolAddress, llvm::JITSymbolFlags::Exported);
    }

    return nullptr;
}

} // namespace gaia

#define DEFINE_WRAP_AND_UNWRAP(Unwrapped, Wrapped) \
static inline Wrapped wrap(Unwrapped unwrapped) { return reinterpret_cast<Wrapped>(unwrapped); } \
static inline Unwrapped unwrap(Wrapped wrapped) { return reinterpret_cast<Unwrapped>(wrapped); }

DEFINE_WRAP_AND_UNWRAP(gaia::JIT*, GaiaJITRef);
DEFINE_WRAP_AND_UNWRAP(gaia::JIT::ModuleHandle*, GaiaJITModuleHandle);

GaiaJITRef GaiaCreateJIT() {
    return wrap(new gaia::JIT());
}

void GaiaDisposeJIT(GaiaJITRef jit) {
    delete unwrap(jit);
}

LLVMTargetMachineRef GaiaGetJITTargetMachine(GaiaJITRef jit) {
    auto& targetMachine = unwrap(jit)->getTargetMachine();
    return reinterpret_cast<LLVMTargetMachineRef>(&targetMachine);
}

GaiaJITModuleHandle GaiaJITAddModule(GaiaJITRef jit, LLVMModuleRef* module) {
    std::unique_ptr<llvm::Module> moduleUPtr(reinterpret_cast<llvm::Module*>(*module));
    *module = nullptr;
    auto moduleHandle = unwrap(jit)->addModule(std::move(moduleUPtr));
    return wrap(new gaia::JIT::ModuleHandle(moduleHandle));
}

void GaiaJITRemoveModule(GaiaJITRef jit, GaiaJITModuleHandle moduleHandle) {
    unwrap(jit)->removeModule(*unwrap(moduleHandle));
}

void GaiaJITDisposeModuleHandle(GaiaJITModuleHandle moduleHandle) {
    delete unwrap(moduleHandle);
}

void* GaiaJITFindSymbolAddress(GaiaJITRef jit, const char* name) {
    if (auto symbol = unwrap(jit)->findSymbol(name)) {
        return reinterpret_cast<void*>(symbol.getAddress());
    }
    return nullptr;
}
