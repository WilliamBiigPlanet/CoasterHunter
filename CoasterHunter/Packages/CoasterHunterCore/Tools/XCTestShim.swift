// A minimal stand-in for XCTest.
//
// Command Line Tools ships the Swift compiler but not XCTest, so `swift test`
// cannot run on a machine without Xcode. Rather than leave the sensor maths
// unverified until Xcode is installed, this provides just enough of the XCTest
// surface for the real test files to compile and run as a plain executable.
//
// The test files import XCTest and are written normally — when Xcode arrives
// they run natively against the real framework and this shim is simply not
// compiled. Nothing in Tests/ knows this exists.

import Foundation

public struct TestFailure {
    public let message: String
    public let file: String
    public let line: Int
}

public enum TestReporter {
    public static var currentTest: String = ""
    public static var failures: [TestFailure] = []
    public static var assertions = 0

    static func fail(_ message: String, _ file: StaticString, _ line: UInt) {
        failures.append(TestFailure(
            message: message,
            file: URL(fileURLWithPath: "\(file)").lastPathComponent,
            line: Int(line)))
    }
}

open class XCTestCase {
    public init() {}
    open func setUp() {}
    open func tearDown() {}
}

struct UnwrapFailure: Error { let message: String }

// MARK: - Assertions

public func XCTAssertEqual<T: Equatable>(
    _ actual: T?, _ expected: T?, _ message: String = "",
    file: StaticString = #file, line: UInt = #line
) {
    TestReporter.assertions += 1
    guard actual != expected else { return }
    let detail = "expected \(describe(expected)) but got \(describe(actual))"
    TestReporter.fail(message.isEmpty ? detail : "\(message) — \(detail)", file, line)
}

public func XCTAssertEqual(
    _ actual: Double, _ expected: Double, accuracy: Double, _ message: String = "",
    file: StaticString = #file, line: UInt = #line
) {
    TestReporter.assertions += 1
    guard abs(actual - expected) > accuracy else { return }
    let detail = "expected \(expected) ± \(accuracy) but got \(actual)"
    TestReporter.fail(message.isEmpty ? detail : "\(message) — \(detail)", file, line)
}

public func XCTAssertTrue(
    _ condition: Bool, _ message: String = "",
    file: StaticString = #file, line: UInt = #line
) {
    TestReporter.assertions += 1
    if !condition {
        TestReporter.fail(message.isEmpty ? "expected true" : message, file, line)
    }
}

public func XCTAssertFalse(
    _ condition: Bool, _ message: String = "",
    file: StaticString = #file, line: UInt = #line
) {
    TestReporter.assertions += 1
    if condition {
        TestReporter.fail(message.isEmpty ? "expected false" : message, file, line)
    }
}

public func XCTAssertNil(
    _ value: Any?, _ message: String = "",
    file: StaticString = #file, line: UInt = #line
) {
    TestReporter.assertions += 1
    if value != nil {
        let detail = "expected nil but got \(describe(value))"
        TestReporter.fail(message.isEmpty ? detail : "\(message) — \(detail)", file, line)
    }
}

public func XCTAssertNotNil(
    _ value: Any?, _ message: String = "",
    file: StaticString = #file, line: UInt = #line
) {
    TestReporter.assertions += 1
    if value == nil {
        TestReporter.fail(message.isEmpty ? "expected a value, got nil" : message, file, line)
    }
}

public func XCTAssertGreaterThan<T: Comparable>(
    _ lhs: T, _ rhs: T, _ message: String = "",
    file: StaticString = #file, line: UInt = #line
) {
    TestReporter.assertions += 1
    guard lhs <= rhs else { return }
    let detail = "expected \(lhs) > \(rhs)"
    TestReporter.fail(message.isEmpty ? detail : "\(message) — \(detail)", file, line)
}

public func XCTAssertGreaterThanOrEqual<T: Comparable>(
    _ lhs: T, _ rhs: T, _ message: String = "",
    file: StaticString = #file, line: UInt = #line
) {
    TestReporter.assertions += 1
    guard lhs < rhs else { return }
    let detail = "expected \(lhs) >= \(rhs)"
    TestReporter.fail(message.isEmpty ? detail : "\(message) — \(detail)", file, line)
}

public func XCTAssertLessThan<T: Comparable>(
    _ lhs: T, _ rhs: T, _ message: String = "",
    file: StaticString = #file, line: UInt = #line
) {
    TestReporter.assertions += 1
    guard lhs >= rhs else { return }
    let detail = "expected \(lhs) < \(rhs)"
    TestReporter.fail(message.isEmpty ? detail : "\(message) — \(detail)", file, line)
}

public func XCTAssertLessThanOrEqual<T: Comparable>(
    _ lhs: T, _ rhs: T, _ message: String = "",
    file: StaticString = #file, line: UInt = #line
) {
    TestReporter.assertions += 1
    guard lhs > rhs else { return }
    let detail = "expected \(lhs) <= \(rhs)"
    TestReporter.fail(message.isEmpty ? detail : "\(message) — \(detail)", file, line)
}

public func XCTUnwrap<T>(
    _ expression: @autoclosure () throws -> T?, _ message: String = "",
    file: StaticString = #file, line: UInt = #line
) throws -> T {
    TestReporter.assertions += 1
    guard let value = try expression() else {
        let detail = message.isEmpty ? "unexpectedly found nil" : message
        TestReporter.fail(detail, file, line)
        throw UnwrapFailure(message: detail)
    }
    return value
}

private func describe(_ value: Any?) -> String {
    guard let value else { return "nil" }
    return "\(value)"
}
