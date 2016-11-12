import Foundation
import REPL
import Driver

if CommandLine.arguments.count == 1 {
    let repl = REPL()
    repl.run()
} else {
    let driver = Driver()

    do {
        let exitStatus = try driver.compileAndExecute(inputFile: CommandLine.arguments[1]) ?? 1
        exit(exitStatus)
    } catch {
        print(error)
        exit(1)
    }
}
