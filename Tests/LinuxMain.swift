import XCTest
import REPLTests
import DriverTests

XCTMain([
    testCase(BasicREPLTests.allTests),
    testCase(DriverCompileTests.allTests),
])
