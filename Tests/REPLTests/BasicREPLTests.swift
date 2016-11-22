#if os(Linux)
import Glibc
#endif
import XCTest
import Parse
@testable import REPL

class BasicREPLTests: XCTestCase {
    func testIntegerLiteralExpression() {
        XCTAssertEqual(runREPL("666\n777\n"), "666\n777\n")
        XCTAssertEqual(runREPL("-666\n-777\n"), "-666\n-777\n")
    }

    func testBooleanLiteralExpression() {
        XCTAssertEqual(runREPL("false\ntrue\n"), "false\ntrue\n")
    }

    func testBooleanLiteralNegation() {
        XCTAssertEqual(runREPL("!false\n!true\n"), "true\nfalse\n")
        XCTAssertEqual(runREPL("!!false\n!!true\n"), "false\ntrue\n")
    }

    func testFloatingPointLiteralExpression() {
        XCTAssertEqual(runREPL("3.1415926536\n0.10\n"), "3.1415926536\n0.1\n")
        XCTAssertEqual(runREPL("-3.1415926536\n-0.10\n"), "-3.1415926536\n-0.1\n")
    }

    func testUnknownVariableExpression() {
        XCTAssertEqual(runREPL("foo\nfoo\n"), "unknown variable 'foo'\nunknown variable 'foo'\n")
    }

    func testSimpleIntegerArithmeticExpressions() {
        XCTAssertEqual(runREPL("4 + 4\n"), "8\n")
        XCTAssertEqual(runREPL("4 - 4\n"), "0\n")
        XCTAssertEqual(runREPL("4 * 4\n"), "16\n")
        XCTAssertEqual(runREPL("4 / 4\n"), "1\n")
    }

    func testSimpleFloatingPointArithmeticExpressions() {
        XCTAssertEqual(runREPL("0.1 + 0.2\n"), "0.3\n")
        XCTAssertEqual(runREPL("0.1 - 0.2\n"), "-0.1\n")
        XCTAssertEqual(runREPL("0.1 * 0.2\n"), "0.02\n")
        XCTAssertEqual(runREPL("0.1 / 0.2\n"), "0.5\n")
    }

    func testArithmeticExpressionsWithPrecedence() {
        XCTAssertEqual(runREPL("6 + 4 * 2\n"), "14\n")
        XCTAssertEqual(runREPL("(6 + 4) * 2\n"), "20\n")
        XCTAssertEqual(runREPL("6 - 4 / 2\n"), "4\n")
        XCTAssertEqual(runREPL("(6 - 4) / 2\n"), "1\n")
    }

    func testNumericComparisonExpressions() {
        XCTAssertEqual(runREPL("0 < -1\n0 < 0\n0 < 1\n"), "false\nfalse\ntrue\n")
        XCTAssertEqual(runREPL("0 > -1\n0 > 0\n0 > 1\n"), "true\nfalse\nfalse\n")
        XCTAssertEqual(runREPL("0 <= -1\n0 <= 0\n0 <= 1\n"), "false\ntrue\ntrue\n")
        XCTAssertEqual(runREPL("0 >= -1\n0 >= 0\n0 >= 1\n"), "true\ntrue\nfalse\n")
        XCTAssertEqual(runREPL("0 == -1\n0 == 0\n0 == 1\n"), "false\ntrue\nfalse\n")
        XCTAssertEqual(runREPL("0 != -1\n0 != 0\n0 != 1\n"), "true\nfalse\ntrue\n")
    }

    func testSimpleIfExpression() {
        XCTAssertEqual(runREPL("if true then 666 else 777\n"), "666\n")
        XCTAssertEqual(runREPL("if false then 666 else 777\n"), "777\n")
        XCTAssertEqual(runREPL("if false then 666 else true\n"), "'then' and 'else' branches must have same type\n")
        XCTAssertEqual(runREPL("if 0 then 666 else 777\n"), "'if' condition requires a Bool expression\n")
        XCTAssertEqual(runREPL("if false 666 else 777\n"), "expected `then` or newline after `if` condition\n")
    }

    func testSimpleIfStatement() {
        var stdoutBuffer = ContiguousArray<CChar>(repeating: 0, count: 256)
        stdoutBuffer.withUnsafeMutableBufferPointer {
            setbuf(stdout, $0.baseAddress)
            XCTAssertEqual(runREPL("extern func puts(s: String)\nif true\n\tputs(\"foo\")\nelse\n\tputs(\"bar\")\nend\n"), "\n")
            XCTAssertEqual(runREPL("extern func puts(s: String)\nif false\n\tputs(\"foo\")\nelse\n\tputs(\"bar\")\nend\n"), "\n")
            XCTAssertEqual(runREPL("extern func puts(s: String)\nif 0\n\tputs(\"a\")\nelse\n\tputs(\"b\")\nend\n"), "'if' condition requires a Bool expression\n")
            XCTAssertEqual(String(cString: $0.baseAddress!), "foo\nbar\n")
            setbuf(stdout, nil)
        }
    }

    func testSimpleFunctionDefinitionAndCall() {
        XCTAssertEqual(runREPL("func foo() return 666\nfoo()\nfoo()\n"), "666\n666\n")
        XCTAssertEqual(runREPL("func foo() return 666 * 777\nfoo()\nfoo()\n"), "517482\n517482\n")
        XCTAssertEqual(runREPL("func foo() return if false then 666 else 777\nfoo()\nfoo()\n"), "777\n777\n")
        XCTAssertEqual(runREPL("func foo() return 666\nfunc foo() return 777\nfoo()\nfoo()\n"), "777\n777\n")
    }

    func testSimpleFunctionWithParameters() {
        XCTAssertEqual(runREPL("func foo(a) return a * 0.5\nfoo(1.0)\nfoo(2.0)\n"), "0.5\n1.0\n")
        XCTAssertEqual(runREPL("func foo(a, b) return a / b\nfoo(1.0, 0.5)\nfoo(0.1, 10.0)\n"), "2.0\n0.01\n")
        XCTAssertEqual(runREPL("func foo(a,b,c) return a+b-c\nfoo(1.0,2.0,3.0)\nfoo(-2.0,-1.0,-0.0)\n"), "0.0\n-3.0\n")
    }

    func testSimpleFunctionWithParametersOfVariousTypes() {
        XCTAssertEqual(runREPL("func foo(a) return -a\nfoo(1.0)\nfoo(1)\n"), "-1.0\n-1\n")
        XCTAssertEqual(runREPL("func foo(a, b) return a / b\nfoo(1.0, 0.5)\nfoo(2, 2)\n"), "2.0\n1\n")
        XCTAssertEqual(runREPL("func foo(a,b,c) return (a==b)!=c\nfoo(1,2,false)\nfoo(1.5,1.5,true)\n"), "false\nfalse\n")
    }

    func testExternCFunctionWithoutReturnValue() {
        var stdoutBuffer = ContiguousArray<CChar>(repeating: 0, count: 256)
        stdoutBuffer.withUnsafeMutableBufferPointer {
            setbuf(stdout, $0.baseAddress)
            XCTAssertEqual(runREPL("extern func putchar(ch)\nputchar(64)\nputchar(65)\n"), "\n\n")
            XCTAssertEqual(String(cString: $0.baseAddress!), "@A")
            setbuf(stdout, nil)
        }
    }

    func testArgumentMismatchError() {
        XCTAssertEqual(runREPL("func foo(a,b) return a-b\nfoo(1)\n"), "wrong number of arguments, expected 2\n")
        XCTAssertEqual(runREPL("func foo(a,b) return a-b\nfoo()\n"), "wrong number of arguments, expected 2\n")
        XCTAssertEqual(runREPL("func answer() return 42\nanswer(false)\n"), "wrong number of arguments, expected 0\n")
    }

    func testVariableDefinition() {
        XCTAssertEqual(runREPL("a = 1\na\na\na = 2\na\n"), "1\n1\n2\n")
        XCTAssertEqual(runREPL("a = \"foo\"\na\na\na = \"\"\na\n"), "\"foo\"\n\"foo\"\n\"\"\n")
    }

    func testCoreLibraryFunctionCall() {
        var stdoutBuffer = ContiguousArray<CChar>(repeating: 0, count: 256)
        stdoutBuffer.withUnsafeMutableBufferPointer {
            setbuf(stdout, $0.baseAddress)
            XCTAssertEqual(runREPL("print(\"foo\")\n"), "\n")
            XCTAssertEqual(String(cString: $0.baseAddress!), "foo\n")
            setbuf(stdout, nil)
        }
    }

    func testIdentifierWithUnderscore() {
        XCTAssertEqual(runREPL("_=1\n__=2\n_a=3\na_=4\n_\n__\n_a\na_"), "1\n2\n3\n4\n")
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
        ("testSimpleIfStatement", testSimpleIfStatement),
        ("testSimpleFunctionDefinitionAndCall", testSimpleFunctionDefinitionAndCall),
        ("testSimpleFunctionWithParameters", testSimpleFunctionWithParameters),
        ("testSimpleFunctionWithParametersOfVariousTypes", testSimpleFunctionWithParametersOfVariousTypes),
        ("testExternCFunctionWithoutReturnValue", testExternCFunctionWithoutReturnValue),
        ("testArgumentMismatchError", testArgumentMismatchError),
        ("testVariableDefinition", testVariableDefinition),
        ("testCoreLibraryFunctionCall", testCoreLibraryFunctionCall),
        ("testIdentifierWithUnderscore", testIdentifierWithUnderscore),
    ]
}

/// Runs the REPL session with the given input. Returns the output produced by the REPL session.
private func runREPL(_ input: String) -> String {
    let input = MockStdin(content: input)
    let output = TextOutputStreamBuffer()
    REPL(inputStream: input, outputStream: output, infoOutputStream: NullTextOutputStream()).run()
    return output.buffer
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

class TextOutputStreamBuffer: TextOutputStream {
    var buffer = ""

    public func write(_ string: String) {
        buffer += string
    }
}

class NullTextOutputStream: TextOutputStream {
    public func write(_ string: String) { /* ignore */ }
}
