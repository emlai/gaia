import Driver

let driver = Driver()
driver.run(inputFiles: CommandLine.arguments.dropFirst())
