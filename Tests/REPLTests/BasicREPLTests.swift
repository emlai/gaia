import XCTest
import Parse
@testable import REPL

class BasicREPLTests: XCTestCase {
    func testIntegerLiteralExpression() {
        XCTAssert(replInput: "666\n777\n", producesOutput: "666\n777\n")
    }

    func testBooleanLiteralExpression() {
        XCTAssert(replInput: "false\ntrue\n", producesOutput: "false\ntrue\n")
    }

    static var allTests = [
        ("testIntegerLiteralExpression", testIntegerLiteralExpression),
        ("testBooleanLiteralExpression", testBooleanLiteralExpression),
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