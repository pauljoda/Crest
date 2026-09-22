import XCTest

@testable import Crest

/// The permission rules themselves are core contracts (`SitePermissionLedgerTests`
/// and `NativeSitePermissionTests` in CrestCore). These cover the native port:
/// the stored document under its long-standing key, and the Space lock wiring.
@MainActor
final class BrowserSitePermissionCenterTests: XCTestCase {
    func testSavedChoicesInTheExistingDefaultsDocumentLoadAndPersistThroughTheCore() throws {
        let suiteName = "BrowserSitePermissionCenterDefaultsContract.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let spaceID = SpaceID()
        let meet = BrowserSiteOrigin(scheme: "https", host: "meet.example", port: 443)
        let installed = BrowserSitePermissionRecord(
            spaceID: spaceID, origin: meet, permission: .camera, decision: .grantPersistently,
            modifiedAt: Date(timeIntervalSinceReferenceDate: 120))
        defaults.set(try JSONEncoder().encode([installed]), forKey: "crest.site-permissions.v1")

        let center = BrowserSitePermissionCenter(
            persistence: UserDefaultsBrowserSitePermissionPersistence(defaults: defaults))
        XCTAssertEqual(center.decision(for: .camera, origin: meet, in: spaceID), .grantPersistently)
        XCTAssertEqual(center.records(in: spaceID), [installed])

        center.setDecision(.denyForSession, for: .microphone, origin: meet, in: spaceID)
        center.setDecision(.grantPersistently, for: .location, origin: meet, in: spaceID)
        let restarted = BrowserSitePermissionCenter(
            persistence: UserDefaultsBrowserSitePermissionPersistence(defaults: defaults))

        XCTAssertEqual(restarted.decision(for: .location, origin: meet, in: spaceID), .grantPersistently)
        XCTAssertEqual(restarted.decision(for: .microphone, origin: meet, in: spaceID), .ask)
        let saved = try JSONDecoder().decode(
            [BrowserSitePermissionRecord].self,
            from: try XCTUnwrap(defaults.data(forKey: "crest.site-permissions.v1")))
        XCTAssertEqual(saved.first, installed)
        XCTAssertEqual(saved.map(\.permission), [.camera, .location])
    }

    func testALockedSpaceNeitherAnswersNorRecordsAndObserversHearRevocations() {
        final class Recorder: BrowserSitePermissionObserver {
            var changes: [BrowserSitePermissionChange] = []
            func sitePermissionsDidChange(_ change: BrowserSitePermissionChange) { changes.append(change) }
        }
        let center = BrowserSitePermissionCenter()
        let recorder = Recorder()
        center.addObserver(recorder)
        let spaceID = SpaceID()
        let origin = BrowserSiteOrigin(scheme: "https", host: "meet.example", port: 443)
        center.setDecision(.grantPersistently, for: .camera, origin: origin, in: spaceID)
        var locked = true
        center.attachSpaceLockState { _ in locked }

        XCTAssertEqual(center.decision(for: .camera, origin: origin, in: spaceID), .ask)
        XCTAssertTrue(center.records(in: spaceID).isEmpty)
        center.setDecision(.grantPersistently, for: .location, origin: origin, in: spaceID)
        XCTAssertEqual(recorder.changes.count, 1)

        locked = false
        XCTAssertEqual(center.decision(for: .location, origin: origin, in: spaceID), .ask)
        center.reset(spaceID: spaceID)
        XCTAssertEqual(recorder.changes.last?.spaceID, spaceID)
        XCTAssertEqual(recorder.changes.last?.revokesAuthorization, true)
        XCTAssertEqual(center.decision(for: .camera, origin: origin, in: spaceID), .ask)
    }

    func testOriginNormalizationPreservesWebDefaultsAndUnknownPorts() throws {
        XCTAssertEqual(
            BrowserSiteOrigin(scheme: "HTTP", host: "News.Example", port: 0),
            BrowserSiteOrigin(scheme: "http", host: "news.example", port: 80)
        )
        XCTAssertEqual(
            BrowserSiteOrigin(scheme: "HTTPS", host: "News.Example", port: -1),
            BrowserSiteOrigin(scheme: "https", host: "news.example", port: 443)
        )
        XCTAssertEqual(
            BrowserSiteOrigin(scheme: "custom", host: "Handler.Example", port: 0),
            BrowserSiteOrigin(scheme: "custom", host: "handler.example", port: 0)
        )
        XCTAssertEqual(
            BrowserSiteOrigin(url: try XCTUnwrap(URL(string: "https://News.Example/path"))),
            BrowserSiteOrigin(scheme: "https", host: "news.example", port: 443)
        )
        XCTAssertNil(BrowserSiteOrigin(url: URL(fileURLWithPath: "/tmp/index.html")))
    }
}
