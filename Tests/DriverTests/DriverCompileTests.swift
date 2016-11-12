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

    static var allTests = [
        ("testSingleFileCompilationWithExitCode", testSingleFileCompilationWithExitCode),
    ]
}
