import XCTest
@testable import Driver

class DriverCompileTests: XCTestCase {
    func testSingleFileCompilationWithExitCode() throws {
        let program = "func foo(a, b) (a + b) / 2\n\nfoo(6, 8)\n"
        try program.write(toFile: "main.gaia", atomically: false, encoding: .utf8)
        let driver = Driver()
        let exitStatus = try driver.compileAndExecute(inputFile: "main.gaia")

        XCTAssertEqual(exitStatus, 7)
        XCTAssert(FileManager.default.fileExists(atPath: "main.gaia"))
        for file in ["main.gaia.o", "main.gaia.out", "main", "a.out"] {
            XCTAssert(!FileManager.default.fileExists(atPath: file))
        }
    }

    func testExternAndMultipleStatementsInMainFunction() throws {
        let program = "extern func putchar(ch)\n\nputchar(71)\nputchar(97)\nputchar(105)\nputchar(97)\n0"
        try program.write(toFile: "main.gaia", atomically: false, encoding: .utf8)
        let driver = Driver()
        let stdoutPipe = Pipe()
        let exitStatus = try driver.compileAndExecute(inputFile: "main.gaia", stdoutPipe: stdoutPipe)

        let output = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        XCTAssertEqual(output, "Gaia")
        XCTAssertEqual(exitStatus, 0)
    }

    func testCompilationOfMultipleCallsToNonExternFunction() throws {
        let program = "func foo(x) 1\nfoo(0)\nfoo(0)\n"
        try program.write(toFile: "main.gaia", atomically: false, encoding: .utf8)
        let driver = Driver()
        let exitStatus = try driver.compileAndExecute(inputFile: "main.gaia")

        XCTAssertEqual(exitStatus, 1)
    }

    func testCompilationOfMultilineFunction() throws {
        let program =
            "extern func putchar(ch)\n\n" +
            "func foo(x)\n" +
            "    putchar(x+15)\n" +
            "    putchar(x-15)\n" +
            "end\n\n" +
            "foo(48)\n"
        try program.write(toFile: "main.gaia", atomically: false, encoding: .utf8)
        let driver = Driver()
        let stdoutPipe = Pipe()
        let exitStatus = try driver.compileAndExecute(inputFile: "main.gaia", stdoutPipe: stdoutPipe)

        let output = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        XCTAssertEqual(output, "?!")
        XCTAssertEqual(exitStatus, 0)
    }

    static var allTests = [
        ("testSingleFileCompilationWithExitCode", testSingleFileCompilationWithExitCode),
        ("testExternAndMultipleStatementsInMainFunction", testExternAndMultipleStatementsInMainFunction),
        ("testCompilationOfMultipleCallsToNonExternFunction", testCompilationOfMultipleCallsToNonExternFunction),
        ("testCompilationOfMultilineFunction", testCompilationOfMultilineFunction),
    ]
}
