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

    func testSimpleIntegerArithmeticExpressions() {
        XCTAssert(replInput: "4 + 4\n", producesOutput: "8\n")
        XCTAssert(replInput: "4 - 4\n", producesOutput: "0\n")
        XCTAssert(replInput: "4 * 4\n", producesOutput: "16\n")
        XCTAssert(replInput: "4 / 4\n", producesOutput: "1\n")
    }

    func testSimpleFloatingPointArithmeticExpressions() {
        XCTAssert(replInput: "0.1 + 0.2\n", producesOutput: "0.3\n")
        XCTAssert(replInput: "0.1 - 0.2\n", producesOutput: "-0.1\n")
        XCTAssert(replInput: "0.1 * 0.2\n", producesOutput: "0.02\n")
        XCTAssert(replInput: "0.1 / 0.2\n", producesOutput: "0.5\n")
    }

    func testArithmeticExpressionsWithPrecedence() {
        XCTAssert(replInput: "6 + 4 * 2\n", producesOutput: "14\n")
        XCTAssert(replInput: "(6 + 4) * 2\n", producesOutput: "20\n")
        XCTAssert(replInput: "6 - 4 / 2\n", producesOutput: "4\n")
        XCTAssert(replInput: "(6 - 4) / 2\n", producesOutput: "1\n")
    }

    func testNumericComparisonExpressions() {
        XCTAssert(replInput: "0 < -1\n0 < 0\n0 < 1\n", producesOutput: "false\nfalse\ntrue\n")
        XCTAssert(replInput: "0 > -1\n0 > 0\n0 > 1\n", producesOutput: "true\nfalse\nfalse\n")
        XCTAssert(replInput: "0 <= -1\n0 <= 0\n0 <= 1\n", producesOutput: "false\ntrue\ntrue\n")
        XCTAssert(replInput: "0 >= -1\n0 >= 0\n0 >= 1\n", producesOutput: "true\ntrue\nfalse\n")
        XCTAssert(replInput: "0 == -1\n0 == 0\n0 == 1\n", producesOutput: "false\ntrue\nfalse\n")
        XCTAssert(replInput: "0 != -1\n0 != 0\n0 != 1\n", producesOutput: "true\nfalse\ntrue\n")
    }

    func testSimpleIfExpression() {
        XCTAssert(replInput: "if true then 666 else 777\n", producesOutput: "666\n")
        XCTAssert(replInput: "if false then 666 else 777\n", producesOutput: "777\n")
        XCTAssert(replInput: "if false then 666 else true\n", producesOutput: "'then' and 'else' branches must have same type\n")
        XCTAssert(replInput: "if 0 then 666 else 777\n", producesOutput: "'if' condition requires a Bool expression\n")
    }

    func testSimpleFunctionDefinitionAndCall() {
        XCTAssert(replInput: "func foo() 666\nfoo()\nfoo()\n", producesOutput: "666\n666\n")
        XCTAssert(replInput: "func foo() 666 * 777\nfoo()\nfoo()\n", producesOutput: "517482\n517482\n")
        XCTAssert(replInput: "func foo() if false then 666 else 777\nfoo()\nfoo()\n", producesOutput: "777\n777\n")
        XCTAssert(replInput: "func foo() 666\nfunc foo() 777\nfoo()\nfoo()\n", producesOutput: "777\n777\n")
    }

    func testSimpleFunctionWithParameters() {
        XCTAssert(replInput: "func foo(a) a * 0.5\nfoo(1.0)\nfoo(2.0)\n", producesOutput: "0.5\n1.0\n")
        XCTAssert(replInput: "func foo(a, b) a / b\nfoo(1.0, 0.5)\nfoo(0.1, 10.0)\n", producesOutput: "2.0\n0.01\n")
        XCTAssert(replInput: "func foo(a,b,c) a+b-c\nfoo(1.0,2.0,3.0)\nfoo(-2.0,-1.0,-0.0)\n", producesOutput: "0.0\n-3.0\n")
    }

    static var allTests = [
        ("testIntegerLiteralExpression", testIntegerLiteralExpression),
        ("testBooleanLiteralExpression", testBooleanLiteralExpression),
        ("testBooleanLiteralNegation", testBooleanLiteralNegation),
        ("testFloatingPointLiteralExpression", testFloatingPointLiteralExpression),
        ("testUnknownVariableExpression", testUnknownVariableExpression),
        ("testSimpleIntegerArithmeticExpressions", testSimpleIntegerArithmeticExpressions),
        ("testSimpleFloatingPointArithmeticExpressions", testSimpleFloatingPointArithmeticExpressions),
        ("testArithmeticExpressionsWithPrecedence", testArithmeticExpressionsWithPrecedence),
        ("testNumericComparisonExpressions", testNumericComparisonExpressions),
        ("testSimpleIfExpression", testSimpleIfExpression),
        ("testSimpleFunctionDefinitionAndCall", testSimpleFunctionDefinitionAndCall),
        ("testSimpleFunctionWithParameters", testSimpleFunctionWithParameters),
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
