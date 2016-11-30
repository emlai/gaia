import Foundation
import Driver

let driver = Driver()

if let emitLLVMIndex = CommandLine.arguments.index(of: "-emit-llvm") {
    CommandLine.arguments.remove(at: emitLLVMIndex)
    driver.emitInLLVMFormat = true
}

let success = driver.compile(inputFiles: Array(CommandLine.arguments.dropFirst()))
exit(success ? 0 : 1)
