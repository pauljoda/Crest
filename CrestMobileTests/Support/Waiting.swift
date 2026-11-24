import XCTest

/// Waits until `condition` holds, asking every 25 milliseconds, and fails the
/// test, naming `description`, once `timeout` passes without it.
@MainActor
func waitUntil(
    _ description: String = "the state to change", timeout: Duration = .seconds(10),
    file: StaticString = #filePath, line: UInt = #line, condition: () async throws -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if try await condition() { return }
        try await Task.sleep(for: .milliseconds(25))
    }
    XCTFail("Timed out waiting for \(description).", file: file, line: line)
}
