import Foundation
import XCTest
@testable import Driver

class DriverCompileTests: XCTestCase {
    func testSingleFileCompilationWithExitCode() throws {
        let result = try compileAndExecute(file: "testSingleFileCompilationWithExitCode")
        XCTAssertEqual(result.programExitStatus, 7)
    }

    func testExternAndMultipleStatementsInMainFunction() throws {
        let result = try compileAndExecute(file: "testExternAndMultipleStatementsInMainFunction")
        XCTAssertEqual(result.programOutput, "Gaia")
        XCTAssertEqual(result.programExitStatus, 0)
    }

    func testCompilationOfMultipleCallsToNonExternFunction() throws {
        let result = try compileAndExecute(file: "testCompilationOfMultipleCallsToNonExternFunction")
        XCTAssertEqual(result.programExitStatus, 1)
    }

    func testCompilationOfMultilineFunction() throws {
        let result = try compileAndExecute(file: "testCompilationOfMultilineFunction")
        XCTAssertEqual(result.programOutput, "?!")
        XCTAssertEqual(result.programExitStatus, 0)
    }

    func testCompilationOfMultilineFunctionWithMultilineIf() throws {
        let result = try compileAndExecute(file: "testCompilationOfMultilineFunctionWithMultilineIf")
        XCTAssertEqual(result.programOutput, "!")
    }

    func testUnknownVariableErrorMessageSourceLocationValidity() throws {
        let result = try compileAndExecute(file: "testUnknownVariableErrorMessageSourceLocationValidity")
        XCTAssertEqual(result.compilerOutput,
                       "testUnknownVariableErrorMessageSourceLocationValidity.gaia:4:8: " +
                       "error: unknown variable 'y'\n" +
                       "    if y < 48\n" +
                       "       ^\n")
    }

    func testMultipleNonExternFunctionCallsInNonExternFunction() throws {
        let result = try compileAndExecute(file: "testMultipleNonExternFunctionCallsInNonExternFunction")
        XCTAssertEqual(result.programExitStatus, 2)
    }

    func testMultiStatementIf() throws {
        let result = try compileAndExecute(file: "testMultiStatementIf")
        XCTAssertEqual(result.programOutput, "abc")
    }

    func testInvalidTypesInArithmeticOperation() throws {
        let result = try compileAndExecute(file: "testInvalidTypesInArithmeticOperation")
        XCTAssertEqual(result.compilerOutput,
                       "testInvalidTypesInArithmeticOperation.gaia:2:3: " +
                       "error: invalid types `Int` and `Float` for arithmetic operation\n" +
                       "5 + 5.0\n" +
                       "  ^\n")
    }

    func testInvalidTypesInComparisonOperation() throws {
        let result = try compileAndExecute(file: "testInvalidTypesInComparisonOperation")
        XCTAssertEqual(result.compilerOutput,
                       "testInvalidTypesInComparisonOperation.gaia:2:5: " +
                       "error: invalid types `Float` and `Void` for comparison operation\n" +
                       "5.0 != putchar(0)\n" +
                       "    ^\n")
    }

    func testArgumentMismatchError() throws {
        let result = try compileAndExecute(file: "testArgumentMismatchError")
        XCTAssertEqual(result.compilerOutput,
                       "testArgumentMismatchError.gaia: error: wrong number of arguments, expected 1\n")

        let result2 = try compileAndExecute(file: "testArgumentMismatchError2")
        XCTAssertEqual(result2.compilerOutput,
                       "testArgumentMismatchError2.gaia:5:5: error: invalid argument type `Int`, expected `Float`\n" +
                       "foo(0)\n" +
                       "    ^\n")

        let result3 = try compileAndExecute(file: "testArgumentMismatchError3")
        XCTAssertEqual(result3.compilerOutput,
                       "testArgumentMismatchError3.gaia:5:5: error: invalid argument type `String`, expected `Int`\n" +
                       "foo(\"bar\")\n" +
                       "    ^\n")
    }

    func testDeclaredReturnTypeWithRecursiveFunction() throws {
        let result = try compileAndExecute(file: "testDeclaredReturnTypeWithRecursiveFunction")
        XCTAssertEqual(result.programExitStatus, 24)
    }

    func testEmptyMainFunction() throws {
        let result = try compileAndExecute(file: "testEmptyMainFunction")
        XCTAssertEqual(result.programExitStatus, 0)
        let result2 = try compileAndExecute(file: "testEmptyMainFunction2")
        XCTAssertEqual(result2.programExitStatus, 0)
    }

    func testBlockComment() throws {
        let result = try compileAndExecute(file: "testBlockComment")
        XCTAssertEqual(result.programExitStatus, 2)

        let result2 = try compileAndExecute(file: "testBlockComment2")
        XCTAssertEqual(result2.compilerOutput, "testBlockComment2.gaia: error: expected `*/` before EOF\n")
    }

    func testVariableDefinition() throws {
        let result = try compileAndExecute(file: "testVariableDefinition")
        XCTAssertEqual(result.programExitStatus, 2)
    }

    func testVariableRedefinitionError() throws {
        let result = try compileAndExecute(file: "testVariableRedefinitionError")
        XCTAssertEqual(result.compilerOutput,
                       "testVariableRedefinitionError.gaia:2:1: error: redefinition of `foo`\n" +
                       "foo = true\n" +
                       "^\n")
    }

    func testStringArgumentToPuts() throws {
        let result = try compileAndExecute(file: "testStringArgumentToPuts")
        XCTAssertEqual(result.programOutput, "🦄\n\n")
    }

    func testUnterminatedStringLiteralError() throws {
        let result = try compileAndExecute(file: "testUnterminatedStringLiteralError")
        XCTAssertEqual(result.compilerOutput,
                       "testUnterminatedStringLiteralError.gaia:1:7: error: unterminated string literal\n" +
                       "foo = \"foo\n" +
                       "      ^\n")
    }

    func testMultiFileCompilation() throws {
        let result = try compileAndExecute(files: "testMultiFileCompilation/main", "testMultiFileCompilation/putsWrapper")
        XCTAssertEqual(result.programOutput, "hello\n")
    }

    func testCoreLibraryFunctionCall() throws {
        let result = try compileAndExecute(file: "testCoreLibraryFunction")
        XCTAssertEqual(result.programOutput, "Hello, World!\n")
    }

    func testInterpretationOfIntegerLiteralAsFloatingPoint() throws {
        let result = try compileAndExecute(file: "testInterpretationOfIntegerLiteralAsFloatingPoint")
        XCTAssertEqual(result.programOutput, "success\n")
    }

    func testOperatorOverloading() throws {
        let result = try compileAndExecute(file: "testOperatorOverloading")
        XCTAssertEqual(result.programOutput, "foo\nbar\nbar\nfoo\n")
    }

    func testInvalidOperatorOverloading() throws {
        let result = try compileAndExecute(file: "testInvalidOperatorOverloading")
        XCTAssertEqual(result.compilerOutput,
                       "testInvalidOperatorOverloading.gaia: error: operator `>` is not overloadable\n")
    }

    func testUnaryOperatorOverloading() throws {
        let result = try compileAndExecute(file: "testUnaryOperatorOverloading")
        XCTAssertEqual(result.programOutput, "foo\n")
    }

    func testInvalidUnaryPlus() throws {
        let result = try compileAndExecute(file: "testInvalidUnaryPlus")
        XCTAssertEqual(result.compilerOutput,
                       "testInvalidUnaryPlus.gaia:1:2: error: invalid operand type `String` for unary `+`\n" +
                       "+\"foo\"\n" +
                       " ^\n")
    }

    func testInvalidNumberOfParametersInOperatorFunction() throws {
        let result = try compileAndExecute(file: "testInvalidNumberOfParametersInOperatorFunction")
        XCTAssertEqual(result.compilerOutput,
                       "testInvalidNumberOfParametersInOperatorFunction.gaia:1:6: " +
                       "error: invalid number of parameters for operator `+`\n" +
                       "func +(a, b, c)\n" +
                       "     ^\n")
    }

    static var allTests = [
        ("testSingleFileCompilationWithExitCode", testSingleFileCompilationWithExitCode),
        ("testExternAndMultipleStatementsInMainFunction", testExternAndMultipleStatementsInMainFunction),
        ("testCompilationOfMultipleCallsToNonExternFunction", testCompilationOfMultipleCallsToNonExternFunction),
        ("testCompilationOfMultilineFunction", testCompilationOfMultilineFunction),
        ("testCompilationOfMultilineFunctionWithMultilineIf", testCompilationOfMultilineFunctionWithMultilineIf),
        ("testUnknownVariableErrorMessageSourceLocationValidity", testUnknownVariableErrorMessageSourceLocationValidity),
        ("testMultipleNonExternFunctionCallsInNonExternFunction", testMultipleNonExternFunctionCallsInNonExternFunction),
        ("testMultiStatementIf", testMultiStatementIf),
        ("testInvalidTypesInArithmeticOperation", testInvalidTypesInArithmeticOperation),
        ("testInvalidTypesInComparisonOperation", testInvalidTypesInComparisonOperation),
        ("testArgumentMismatchError", testArgumentMismatchError),
        ("testDeclaredReturnTypeWithRecursiveFunction", testDeclaredReturnTypeWithRecursiveFunction),
        ("testEmptyMainFunction", testEmptyMainFunction),
        ("testBlockComment", testBlockComment),
        ("testVariableDefinition", testVariableDefinition),
        ("testVariableRedefinitionError", testVariableRedefinitionError),
        ("testStringArgumentToPuts", testStringArgumentToPuts),
        ("testUnterminatedStringLiteralError", testUnterminatedStringLiteralError),
        ("testMultiFileCompilation", testMultiFileCompilation),
        ("testCoreLibraryFunctionCall", testCoreLibraryFunctionCall),
        ("testInterpretationOfIntegerLiteralAsFloatingPoint", testInterpretationOfIntegerLiteralAsFloatingPoint),
        ("testOperatorOverloading", testOperatorOverloading),
        ("testInvalidOperatorOverloading", testInvalidOperatorOverloading),
        ("testUnaryOperatorOverloading", testUnaryOperatorOverloading),
        ("testInvalidUnaryPlus", testInvalidUnaryPlus),
        ("testInvalidNumberOfParametersInOperatorFunction", testInvalidNumberOfParametersInOperatorFunction),
    ]
}

class TextOutputStreamBuffer: TextOutputStream {
    var buffer = ""

    public func write(_ string: String) {
        buffer += string
    }
}

private struct CompileAndExecuteResult {
    let compilerOutput: String
    let programOutput: String?
    let programExitStatus: Int32?
}

/// Convenience wrapper around `Driver.compileAndExecute`. Returns the exit status.
private func compileAndExecute(files fileNamesWithoutExtension: String...) throws -> CompileAndExecuteResult {
    let inputsDirectoryPath = URL(fileURLWithPath: #file).deletingLastPathComponent().path + "/Inputs"
    if !FileManager.default.changeCurrentDirectoryPath(inputsDirectoryPath) { fatalError() }

    let compilerOutput = TextOutputStreamBuffer()
    let programOutputPipe = Pipe()
    let driver = Driver(outputStream: compilerOutput)
    let programExitStatus = try driver.compileAndExecute(inputFiles: fileNamesWithoutExtension.map { $0 + ".gaia" },
                                                         stdoutPipe: programOutputPipe)
    let programOutput: String?
    if programExitStatus != nil {
        programOutput = String(data: programOutputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    } else {
        programOutput = nil
    }

    return CompileAndExecuteResult(compilerOutput: compilerOutput.buffer,
                                   programOutput: programOutput,
                                   programExitStatus: programExitStatus)
}

private func compileAndExecute(file fileNameWithoutExtension: String) throws -> CompileAndExecuteResult {
    return try compileAndExecute(files: fileNameWithoutExtension)
}
