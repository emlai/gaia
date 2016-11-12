import Driver

let driver = Driver()
driver.compile(inputFiles: CommandLine.arguments.dropFirst())
