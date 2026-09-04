import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserChromeDebuggerTargetTests: XCTestCase {
    func testGetTargetsReportsOnlyTheAttachedTab() async throws {
        try await withTarget { domain, fixture, _ in
            let response = try await domain.execute("Target.getTargets", parameters: [:])
            let infos = try XCTUnwrap(response["targetInfos"] as? [[String: Any]])
            XCTAssertEqual(infos.count, 1, "A session may only see the tab it was granted.")
            let info = try XCTUnwrap(infos.first)
            XCTAssertEqual(info["targetId"] as? String, fixture.target.tabID.rawValue.uuidString)
            XCTAssertEqual(info["type"] as? String, "page")
            XCTAssertEqual(info["attached"] as? Bool, true)
            XCTAssertEqual(info["canAccessOpener"] as? Bool, false)
            XCTAssertEqual(info["browserContextId"] as? String, fixture.target.spaceID.rawValue.uuidString)
            XCTAssertTrue(try XCTUnwrap(info["url"] as? String).contains("crest.test"))
            XCTAssertEqual(info["title"] as? String, "Crest domain test")
        }
    }

    func testCloseTargetClosesOnlyTheAttachedTab() async throws {
        try await withTarget { domain, fixture, host in
            do {
                _ = try await domain.execute(
                    "Target.closeTarget", parameters: ["targetId": TabID().rawValue.uuidString])
                XCTFail("A session must not close a tab it was never granted.")
            } catch BrowserChromeDebuggerProtocolError.invalidParameter("targetId") {}
            XCTAssertTrue(host.closed.isEmpty)
            let response = try await domain.execute(
                "Target.closeTarget", parameters: ["targetId": fixture.target.tabID.rawValue.uuidString])
            XCTAssertEqual(response["success"] as? Bool, true)
            XCTAssertEqual(host.closed, [fixture.target])
        }
    }

    func testEmulationAndOtherTargetCommandsReportUnsupported() async throws {
        try await withTarget { domain, _, _ in
            for method in [
                "Emulation.setDeviceMetricsOverride", "Emulation.clearDeviceMetricsOverride",
                "Emulation.setUserAgentOverride", "Target.createTarget", "Target.attachToTarget",
            ] {
                do {
                    _ = try await domain.execute(method, parameters: [:])
                    XCTFail("An unimplemented command must report unsupported: \(method)")
                } catch BrowserChromeDebuggerProtocolError.unsupportedCommand(let refused) {
                    XCTAssertEqual(refused, method)
                }
            }
        }
    }

    private func withTarget(
        _ operation: (
            BrowserChromeDebuggerTarget, BrowserChromeDebuggerDomainFixture, BrowserChromeDebuggerTabHostDouble
        ) async throws -> Void
    ) async throws {
        let fixture = try await BrowserChromeDebuggerDomainFixture.make()
        defer { fixture.tearDown() }
        let host = BrowserChromeDebuggerTabHostDouble()
        let domain = BrowserChromeDebuggerTarget(
            target: fixture.target, webView: fixture.page, tabHost: host)
        try await operation(domain, fixture, host)
    }
}
