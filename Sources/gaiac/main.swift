import Foundation
import Driver

let driver = Driver()
let success = driver.compile(inputFiles: CommandLine.arguments.dropFirst())
exit(success ? 0 : 1)
