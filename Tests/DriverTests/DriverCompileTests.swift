import XCTest
@testable import Driver

class DriverCompileTests: XCTestCase {
    func testSingleFileCompilationWithExitCode() throws {
        let program = "func foo(a, b) (a + b) / 2\n\nfoo(6, 8)\n"
        try program.write(toFile: "main.gaia", atomically: false, encoding: .utf8)
        let driver = Driver()
        driver.run(inputFiles: ["main.gaia"])
        XCTAssert(FileManager.default.fileExists(atPath: "main.gaia.o"))
        try FileManager.default.removeItem(atPath: "main.gaia")

        let linkProcess = Process()
        linkProcess.launchPath = "/usr/bin/env"
        linkProcess.arguments = ["cc", "main.gaia.o"]
        linkProcess.launch()
        linkProcess.waitUntilExit()
        XCTAssertEqual(linkProcess.terminationStatus, 0)
        try FileManager.default.removeItem(atPath: "main.gaia.o")

        let runProcess = Process()
        runProcess.launchPath = "a.out"
        runProcess.launch()
        runProcess.waitUntilExit()
        XCTAssertEqual(runProcess.terminationStatus, 7)
        try FileManager.default.removeItem(atPath: "a.out")
    }

    func testExternAndMultipleStatementsInMainFunction() throws {
        let program = "extern func putchar(ch)\n\nputchar(71)\nputchar(97)\nputchar(105)\nputchar(97)\n0"
        try program.write(toFile: "main.gaia", atomically: false, encoding: .utf8)
        let driver = Driver()
        driver.run(inputFiles: ["main.gaia"])
        XCTAssert(FileManager.default.fileExists(atPath: "main.gaia.o"))
        try FileManager.default.removeItem(atPath: "main.gaia")

        let linkProcess = Process()
        linkProcess.launchPath = "/usr/bin/env"
        linkProcess.arguments = ["cc", "main.gaia.o"]
        linkProcess.launch()
        linkProcess.waitUntilExit()
        XCTAssertEqual(linkProcess.terminationStatus, 0)
        try FileManager.default.removeItem(atPath: "main.gaia.o")

        let stdoutPipe = Pipe()
        let runProcess = Process()
        runProcess.launchPath = "a.out"
        runProcess.standardOutput = stdoutPipe
        runProcess.launch()
        runProcess.waitUntilExit()
        XCTAssertEqual(runProcess.terminationStatus, 0)
        try FileManager.default.removeItem(atPath: "a.out")

        let output = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        XCTAssertEqual(output, "Gaia")
    }

    static var allTests = [
        ("testSingleFileCompilationWithExitCode", testSingleFileCompilationWithExitCode),
        ("testExternAndMultipleStatementsInMainFunction", testExternAndMultipleStatementsInMainFunction)
    ]
}
