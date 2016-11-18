import Foundation
import Driver

let driver = Driver()
let success = driver.compile(inputFiles: Array(CommandLine.arguments.dropFirst()))
exit(success ? 0 : 1)
