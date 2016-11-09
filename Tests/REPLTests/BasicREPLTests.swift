import XCTest
import Parse
@testable import REPL

class BasicREPLTests: XCTestCase {
    func testIntegerLiteralExpression() {
        XCTAssert(replInput: "666\n777\n", producesOutput: "666\n777\n")
        XCTAssert(replInput: "-666\n-777\n", producesOutput: "-666\n-777\n")
    }

    func testBooleanLiteralExpression() {
        XCTAssert(replInput: "false\ntrue\n", producesOutput: "false\ntrue\n")
    }

    func testBooleanLiteralNegation() {
        XCTAssert(replInput: "!false\n!true\n", producesOutput: "true\nfalse\n")
        XCTAssert(replInput: "!!false\n!!true\n", producesOutput: "false\ntrue\n")
    }

    func testFloatingPointLiteralExpression() {
        XCTAssert(replInput: "3.1415926536\n0.10\n", producesOutput: "3.1415926536\n0.1\n")
        XCTAssert(replInput: "-3.1415926536\n-0.10\n", producesOutput: "-3.1415926536\n-0.1\n")
    }

    func testUnknownVariableExpression() {
        XCTAssert(replInput: "foo\nfoo\n", producesOutput: "unknown variable 'foo'\nunknown variable 'foo'\n")
    }

    static var allTests = [
        ("testIntegerLiteralExpression", testIntegerLiteralExpression),
        ("testBooleanLiteralExpression", testBooleanLiteralExpression),
        ("testBooleanLiteralNegation", testBooleanLiteralNegation),
        ("testFloatingPointLiteralExpression", testFloatingPointLiteralExpression),
        ("testUnknownVariableExpression", testUnknownVariableExpression),
    ]
}

private func XCTAssert(replInput input: String, producesOutput expectedOutput: String) {
    let input = MockStdin(content: input)
    let output = MockStdout(expected: expectedOutput)
    REPL(inputStream: input, outputStream: output).run()
    XCTAssert(output.expected.isEmpty, "expected \"\(output.expected.escaped)\", got end of output")
}

class MockStdin: TextInputStream {
    private var content: String
    private var eof: Bool

    init(content: String) {
        self.content = content
        eof = false
    }

    func read() -> UnicodeScalar? {
        if eof { return nil }
        return content.unicodeScalars.popFirst()
    }

    func unread(_ character: UnicodeScalar?) {
        if let c = character {
            content.unicodeScalars.insert(c, at: content.unicodeScalars.startIndex)
        }
        eof = character == nil
    }
}

class MockStdout: TextOutputStream {
    private(set) var expected: String

    init(expected: String) {
        self.expected = expected
    }

    public func write(_ string: String) {
        if expected.hasPrefix(string) {
            expected.removeSubrange(expected.range(of: string)!)
        } else {
            XCTFail("expected \"\(expected.escaped)\", got \"\(string.escaped)\"")
        }
    }
}

extension String {
    var escaped: String {
        return replacingOccurrences(of: "\n", with: "\\n")
    }
}
