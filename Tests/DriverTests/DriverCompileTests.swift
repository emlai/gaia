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

    func testCompilationOfMultilineFunctionWithMultilineIf() throws {
        let program =
            "extern func putchar(ch)\n\n" +
            "func foo(x)\n" +
            "    if x < 48\n" +
            "        putchar(x+15)\n" +
            "    else\n" +
            "        putchar(x-15)\n" +
            "end\n\n" +
            "foo(48)\n"
        try program.write(toFile: "main.gaia", atomically: false, encoding: .utf8)
        let driver = Driver()
        let stdoutPipe = Pipe()
        _ = try driver.compileAndExecute(inputFile: "main.gaia", stdoutPipe: stdoutPipe)

        let output = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        XCTAssertEqual(output, "!")
    }

    func testUnknownVariableErrorMessageSourceLocationValidity() throws {
        let program =
            "\n\n" +
            "func foo(x)\n" +
            "    if y < 48\n" +
            "        1\n" +
            "    else\n" +
            "        2\n" +
            "end\n\n" +
            "foo(48)\n"
        try program.write(toFile: "main.gaia", atomically: false, encoding: .utf8)
        let output = TextOutputStreamBuffer()
        let driver = Driver(outputStream: output)
        _ = try driver.compileAndExecute(inputFile: "main.gaia")

        XCTAssertEqual(output.buffer, "main.gaia:4:8: error: unknown variable 'y'\n")
    }

    func testMultipleNonExternFunctionCallsInNonExternFunction() throws {
        let program =
            "func foo(x) x+1\n" +
            "func bar(y)\n" +
            "    foo(y)\n" +
            "    foo(y)\n" +
            "end\n\n" +
            "bar(1)\n"
        try program.write(toFile: "main.gaia", atomically: false, encoding: .utf8)
        let driver = Driver()
        let exitStatus = try driver.compileAndExecute(inputFile: "main.gaia")

        XCTAssertEqual(exitStatus, 2)
    }

    static var allTests = [
        ("testSingleFileCompilationWithExitCode", testSingleFileCompilationWithExitCode),
        ("testExternAndMultipleStatementsInMainFunction", testExternAndMultipleStatementsInMainFunction),
        ("testCompilationOfMultipleCallsToNonExternFunction", testCompilationOfMultipleCallsToNonExternFunction),
        ("testCompilationOfMultilineFunction", testCompilationOfMultilineFunction),
        ("testCompilationOfMultilineFunctionWithMultilineIf", testCompilationOfMultilineFunctionWithMultilineIf),
        ("testUnknownVariableErrorMessageSourceLocationValidity", testUnknownVariableErrorMessageSourceLocationValidity),
        ("testMultipleNonExternFunctionCallsInNonExternFunction", testMultipleNonExternFunctionCallsInNonExternFunction),
    ]
}

class TextOutputStreamBuffer: TextOutputStream {
    var buffer = ""

    public func write(_ string: String) {
        buffer += string
    }
}
