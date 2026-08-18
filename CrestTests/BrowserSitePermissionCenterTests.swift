import XCTest

@testable import Crest

@MainActor
final class BrowserSitePermissionCenterTests: XCTestCase {
    func testPermissionEnumCodableRawValuesRemainStable() throws {
        let mediaPermissions: [(BrowserMediaPermission, String)] = [
            (.camera, "camera"),
            (.microphone, "microphone"),
            (.cameraAndMicrophone, "cameraAndMicrophone"),
        ]
        let sitePermissions: [(BrowserSitePermission, String)] = [
            (.camera, "camera"),
            (.microphone, "microphone"),
            (.cameraAndMicrophone, "cameraAndMicrophone"),
            (.location, "location"),
            (.notifications, "notifications"),
            (.popups, "popups"),
            (.automaticDownloads, "automaticDownloads"),
            (.externalApplications, "externalApplications"),
        ]
        let decisions: [(BrowserSitePermissionDecision, String)] = [
            (.ask, "ask"),
            (.grantForSession, "grantForSession"),
            (.denyForSession, "denyForSession"),
            (.grantPersistently, "grantPersistently"),
            (.denyPersistently, "denyPersistently"),
        ]

        for (permission, rawValue) in mediaPermissions {
            try assertCodableRawValue(permission, equals: rawValue)
        }
        for (permission, rawValue) in sitePermissions {
            try assertCodableRawValue(permission, equals: rawValue)
        }
        for (decision, rawValue) in decisions {
            try assertCodableRawValue(decision, equals: rawValue)
        }
    }

    func testPermissionRecordCodableKeysRemainStable() throws {
        let recordID = try XCTUnwrap(
            UUID(uuidString: "B0479F10-CECA-4D7B-A4C9-86B41CB624A4")
        )
        let spaceUUID = try XCTUnwrap(
            UUID(uuidString: "03E3E543-21FB-44F0-87BB-EF4375796517")
        )
        let record = BrowserSitePermissionRecord(
            id: recordID,
            spaceID: SpaceID(rawValue: spaceUUID),
            origin: BrowserSiteOrigin(
                scheme: "https",
                host: "downloads.example",
                port: 443
            ),
            permission: .automaticDownloads,
            decision: .denyPersistently,
            modifiedAt: Date(timeIntervalSinceReferenceDate: 120)
        )

        let encoded = try JSONEncoder().encode(record)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let origin = try XCTUnwrap(object["origin"] as? [String: Any])
        let spaceID = try XCTUnwrap(object["spaceID"] as? [String: Any])

        XCTAssertEqual(
            Set(object.keys),
            ["id", "spaceID", "origin", "permission", "decision", "modifiedAt"]
        )
        XCTAssertEqual(Set(origin.keys), ["scheme", "host", "port"])
        XCTAssertEqual(Set(spaceID.keys), ["rawValue"])
        XCTAssertEqual(object["permission"] as? String, "automaticDownloads")
        XCTAssertEqual(object["decision"] as? String, "denyPersistently")
        XCTAssertNil(object["detail"])
    }

    func testDefaultPersistenceKeyAndMalformedDataFallbackRemainStable() throws {
        let suiteName = "BrowserSitePermissionCenterDefaultsContract.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let persistence = UserDefaultsBrowserSitePermissionPersistence(defaults: defaults)
        let record = BrowserSitePermissionRecord(
            spaceID: SpaceID(),
            origin: BrowserSiteOrigin(scheme: "https", host: "meet.example", port: 443),
            permission: .camera,
            decision: .grantPersistently
        )

        persistence.save([record])

        XCTAssertNotNil(defaults.data(forKey: "crest.site-permissions.v1"))
        XCTAssertEqual(persistence.load(), [record])

        defaults.set(Data("not-json".utf8), forKey: "crest.site-permissions.v1")
        XCTAssertEqual(persistence.load(), [])
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

    func testRecordsRetainExistingPresentationOrdering() {
        let spaceID = SpaceID()
        let origin = BrowserSiteOrigin(
            scheme: "https",
            host: "permissions.example",
            port: 443
        )
        let records = [
            BrowserSitePermissionRecord(
                spaceID: spaceID,
                origin: origin,
                permission: .popups,
                decision: .grantPersistently
            ),
            BrowserSitePermissionRecord(
                spaceID: spaceID,
                origin: origin,
                permission: .externalApplications,
                detail: "mailto",
                decision: .grantPersistently
            ),
            BrowserSitePermissionRecord(
                spaceID: spaceID,
                origin: origin,
                permission: .camera,
                decision: .grantPersistently
            ),
            BrowserSitePermissionRecord(
                spaceID: spaceID,
                origin: origin,
                permission: .automaticDownloads,
                decision: .grantPersistently
            ),
            BrowserSitePermissionRecord(
                spaceID: spaceID,
                origin: origin,
                permission: .microphone,
                decision: .grantPersistently
            ),
            BrowserSitePermissionRecord(
                spaceID: spaceID,
                origin: origin,
                permission: .cameraAndMicrophone,
                decision: .grantPersistently
            ),
        ]
        let center = BrowserSitePermissionCenter(
            persistence: InMemoryBrowserSitePermissionPersistence(records: records)
        )

        XCTAssertEqual(
            center.records(in: spaceID).map(\.displayLabel),
            [
                "Automatic Downloads",
                "Camera",
                "Camera & Microphone",
                "External Apps (mailto)",
                "Microphone",
                "Pop-ups",
            ]
        )
    }

    func testHostedNotificationBoundarySupportsOnlyLivePageDelivery() {
        let capabilities = BrowserHostedWebNotificationCapabilities.wkWebView

        XCTAssertTrue(capabilities.supportsPermissionDelegation)
        XCTAssertTrue(capabilities.supportsForegroundPageDelivery)
        XCTAssertFalse(capabilities.supportsBackgroundPushDelivery)
        XCTAssertEqual(capabilities.systemOwner, .crestWhilePageIsLoaded)
        XCTAssertTrue(BrowserSitePermission.allCases.map(\.settingsLabel).contains("Notifications"))
    }

    func testHostedNotificationsRequireHTTPSOrLoopbackHTTP() {
        XCTAssertTrue(
            BrowserHostedWebNotificationOriginPolicy.allows(
                BrowserSiteOrigin(scheme: "https", host: "news.example", port: 443)
            )
        )
        XCTAssertTrue(
            BrowserHostedWebNotificationOriginPolicy.allows(
                BrowserSiteOrigin(scheme: "http", host: "localhost", port: 8080)
            )
        )
        XCTAssertFalse(
            BrowserHostedWebNotificationOriginPolicy.allows(
                BrowserSiteOrigin(scheme: "http", host: "news.example", port: 80)
            )
        )
    }

    func testUnknownPermissionAsksByDefault() {
        let center = BrowserSitePermissionCenter()
        let origin = BrowserSiteOrigin(scheme: "https", host: "meet.example", port: 443)

        XCTAssertEqual(
            center.decision(for: .camera, origin: origin, in: SpaceID()),
            .ask
        )
    }

    func testDecisionIsScopedToExactSpaceOriginAndCapability() {
        let center = BrowserSitePermissionCenter()
        let work = SpaceID()
        let personal = SpaceID()
        let origin = BrowserSiteOrigin(scheme: "https", host: "meet.example", port: 443)
        let otherPort = BrowserSiteOrigin(scheme: "https", host: "meet.example", port: 8443)
        center.setDecision(.grantForSession, for: .camera, origin: origin, in: work)

        XCTAssertEqual(center.decision(for: .camera, origin: origin, in: work), .grantForSession)
        XCTAssertEqual(center.decision(for: .microphone, origin: origin, in: work), .ask)
        XCTAssertEqual(center.decision(for: .camera, origin: otherPort, in: work), .ask)
        XCTAssertEqual(center.decision(for: .camera, origin: origin, in: personal), .ask)
    }

    func testPopupsAndAutomaticDownloadsRemainIndependentBySpace() {
        let center = BrowserSitePermissionCenter()
        let work = SpaceID()
        let personal = SpaceID()
        let origin = BrowserSiteOrigin(scheme: "https", host: "news.example", port: 443)

        center.setDecision(.grantPersistently, for: .popups, origin: origin, in: work)
        center.setDecision(
            .denyPersistently,
            for: .automaticDownloads,
            origin: origin,
            in: work
        )

        XCTAssertEqual(
            center.decision(for: .popups, origin: origin, in: work),
            .grantPersistently
        )
        XCTAssertEqual(
            center.decision(for: .automaticDownloads, origin: origin, in: work),
            .denyPersistently
        )
        XCTAssertEqual(center.decision(for: .popups, origin: origin, in: personal), .ask)
        XCTAssertEqual(
            center.decision(for: .automaticDownloads, origin: origin, in: personal),
            .ask
        )
    }

    func testDenyAndResetRemainSpaceLocal() {
        let center = BrowserSitePermissionCenter()
        let work = SpaceID()
        let personal = SpaceID()
        let origin = BrowserSiteOrigin(scheme: "https", host: "meet.example", port: 443)
        center.setDecision(.denyForSession, for: .microphone, origin: origin, in: work)
        center.setDecision(.grantForSession, for: .microphone, origin: origin, in: personal)

        center.reset(spaceID: work)

        XCTAssertEqual(center.decision(for: .microphone, origin: origin, in: work), .ask)
        XCTAssertEqual(center.decision(for: .microphone, origin: origin, in: personal), .grantForSession)
    }

    func testPersistentDecisionSurvivesCenterReconstruction() {
        let persistence = InMemoryBrowserSitePermissionPersistence()
        let spaceID = SpaceID()
        let origin = BrowserSiteOrigin(scheme: "https", host: "meet.example", port: 443)
        let firstCenter = BrowserSitePermissionCenter(persistence: persistence)

        firstCenter.setDecision(
            .grantPersistently,
            for: .camera,
            origin: origin,
            in: spaceID
        )
        let secondCenter = BrowserSitePermissionCenter(persistence: persistence)

        XCTAssertEqual(
            secondCenter.decision(for: .camera, origin: origin, in: spaceID),
            .grantPersistently
        )
        XCTAssertEqual(secondCenter.records(in: spaceID).count, 1)
    }

    func testUserDefaultsPersistenceSurvivesAdapterReconstruction() throws {
        let suiteName = "BrowserSitePermissionCenterTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "site-permissions"
        let spaceID = SpaceID()
        let origin = BrowserSiteOrigin(scheme: "https", host: "meet.example", port: 443)

        let firstPersistence = UserDefaultsBrowserSitePermissionPersistence(
            defaults: defaults,
            key: key
        )
        let firstCenter = BrowserSitePermissionCenter(persistence: firstPersistence)
        firstCenter.setDecision(
            .denyPersistently,
            for: .microphone,
            origin: origin,
            in: spaceID
        )

        let secondPersistence = UserDefaultsBrowserSitePermissionPersistence(
            defaults: defaults,
            key: key
        )
        let secondCenter = BrowserSitePermissionCenter(persistence: secondPersistence)

        XCTAssertEqual(
            secondCenter.decision(for: .microphone, origin: origin, in: spaceID),
            .denyPersistently
        )
        XCTAssertEqual(secondCenter.records(in: spaceID).count, 1)
    }

    func testSessionOverrideDoesNotPersistOrReplaceSavedChoice() {
        let persistence = InMemoryBrowserSitePermissionPersistence()
        let spaceID = SpaceID()
        let origin = BrowserSiteOrigin(scheme: "https", host: "meet.example", port: 443)
        let firstCenter = BrowserSitePermissionCenter(persistence: persistence)
        firstCenter.setDecision(.grantPersistently, for: .camera, origin: origin, in: spaceID)
        firstCenter.setDecision(.denyForSession, for: .camera, origin: origin, in: spaceID)

        XCTAssertEqual(firstCenter.decision(for: .camera, origin: origin, in: spaceID), .denyForSession)

        let secondCenter = BrowserSitePermissionCenter(persistence: persistence)
        XCTAssertEqual(
            secondCenter.decision(for: .camera, origin: origin, in: spaceID),
            .grantPersistently
        )
    }

    func testChangingSavedDecisionPreservesRecordIdentityAndResetRemovesIt() throws {
        let persistence = InMemoryBrowserSitePermissionPersistence()
        let center = BrowserSitePermissionCenter(persistence: persistence)
        let spaceID = SpaceID()
        let origin = BrowserSiteOrigin(scheme: "https", host: "meet.example", port: 443)
        center.setDecision(.grantPersistently, for: .microphone, origin: origin, in: spaceID)
        let originalID = try XCTUnwrap(center.records(in: spaceID).first?.id)

        center.setDecision(.denyPersistently, for: .microphone, origin: origin, in: spaceID)

        XCTAssertEqual(center.records(in: spaceID).first?.id, originalID)
        XCTAssertEqual(center.records(in: spaceID).first?.decision, .denyPersistently)

        center.reset(recordID: originalID)

        XCTAssertEqual(center.decision(for: .microphone, origin: origin, in: spaceID), .ask)
        XCTAssertTrue(persistence.records.isEmpty)
    }

    func testResetSpaceRemovesOnlyThatSpacesPersistentAndSessionDecisions() {
        let persistence = InMemoryBrowserSitePermissionPersistence()
        let center = BrowserSitePermissionCenter(persistence: persistence)
        let work = SpaceID()
        let personal = SpaceID()
        let origin = BrowserSiteOrigin(scheme: "https", host: "meet.example", port: 443)
        center.setDecision(.grantPersistently, for: .camera, origin: origin, in: work)
        center.setDecision(.denyPersistently, for: .camera, origin: origin, in: personal)
        center.setDecision(.denyForSession, for: .microphone, origin: origin, in: work)

        center.reset(spaceID: work)

        XCTAssertEqual(center.decision(for: .camera, origin: origin, in: work), .ask)
        XCTAssertEqual(center.decision(for: .microphone, origin: origin, in: work), .ask)
        XCTAssertEqual(center.decision(for: .camera, origin: origin, in: personal), .denyPersistently)
        XCTAssertEqual(persistence.records.map(\.spaceID), [personal])
    }

    func testOriginDisplayNameOmitsOnlyDefaultPorts() {
        XCTAssertEqual(
            BrowserSiteOrigin(scheme: "https", host: "Meet.Example", port: 443).displayName,
            "https://meet.example"
        )
        XCTAssertEqual(
            BrowserSiteOrigin(scheme: "https", host: "meet.example", port: 8443).displayName,
            "https://meet.example:8443"
        )
        XCTAssertEqual(
            BrowserSiteOrigin(scheme: "https", host: "meet.example", port: 0).displayName,
            "https://meet.example"
        )
    }

    func testExistingMediaPermissionRecordDecodesAfterCapabilityExpansion() throws {
        let recordID = UUID()
        let spaceID = SpaceID()
        let json = """
            [{
              "id":"\(recordID.uuidString)",
              "spaceID":{"rawValue":"\(spaceID.rawValue.uuidString)"},
              "origin":{"scheme":"https","host":"meet.example","port":443},
              "permission":"camera",
              "decision":"grantPersistently",
              "modifiedAt":0
            }]
            """

        let records = try JSONDecoder().decode(
            [BrowserSitePermissionRecord].self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(records.first?.permission, .camera)
    }

    func testExternalApplicationChoicesAreScopedToTheRequestedScheme() {
        let center = BrowserSitePermissionCenter()
        let spaceID = SpaceID()
        let origin = BrowserSiteOrigin(scheme: "https", host: "mail.example", port: 443)

        center.setDecision(
            .grantPersistently,
            for: .externalApplications,
            origin: origin,
            detail: "mailto",
            in: spaceID
        )

        XCTAssertEqual(
            center.decision(
                for: .externalApplications,
                origin: origin,
                detail: "mailto",
                in: spaceID
            ),
            .grantPersistently
        )
        XCTAssertEqual(
            center.decision(
                for: .externalApplications,
                origin: origin,
                detail: "zoommtg",
                in: spaceID
            ),
            .ask
        )
        XCTAssertEqual(
            center.records(in: spaceID).first?.detail,
            "mailto"
        )
        XCTAssertEqual(
            center.records(in: spaceID).first?.displayLabel,
            "External Apps (mailto)"
        )
    }

    func testASchemelessRuleCoversEverySchemeWithoutItsOwnChoice() {
        let center = BrowserSitePermissionCenter()
        let spaceID = SpaceID()
        let origin = BrowserSiteOrigin(scheme: "https", host: "mail.example", port: 443)

        center.setDecision(
            .denyPersistently,
            for: .externalApplications,
            origin: origin,
            in: spaceID
        )
        center.setDecision(
            .grantPersistently,
            for: .externalApplications,
            origin: origin,
            detail: "mailto",
            in: spaceID
        )

        XCTAssertEqual(
            center.decision(
                for: .externalApplications,
                origin: origin,
                detail: "mailto",
                in: spaceID
            ),
            .grantPersistently,
            "The scheme-specific choice must win over the site-wide rule."
        )
        XCTAssertEqual(
            center.decision(
                for: .externalApplications,
                origin: origin,
                detail: "zoommtg",
                in: spaceID
            ),
            .denyPersistently
        )
        XCTAssertEqual(center.records(in: spaceID).count, 2)
    }

    func testResettingOneSchemeLeavesTheOtherSchemesAlone() throws {
        let persistence = InMemoryBrowserSitePermissionPersistence()
        let center = BrowserSitePermissionCenter(persistence: persistence)
        let spaceID = SpaceID()
        let origin = BrowserSiteOrigin(scheme: "https", host: "mail.example", port: 443)
        center.setDecision(
            .grantPersistently,
            for: .externalApplications,
            origin: origin,
            detail: "mailto",
            in: spaceID
        )
        center.setDecision(
            .grantPersistently,
            for: .externalApplications,
            origin: origin,
            detail: "tel",
            in: spaceID
        )

        center.setDecision(
            .ask,
            for: .externalApplications,
            origin: origin,
            detail: "mailto",
            in: spaceID
        )

        XCTAssertEqual(
            center.decision(
                for: .externalApplications,
                origin: origin,
                detail: "mailto",
                in: spaceID
            ),
            .ask
        )
        XCTAssertEqual(
            center.decision(
                for: .externalApplications,
                origin: origin,
                detail: "tel",
                in: spaceID
            ),
            .grantPersistently
        )
        XCTAssertEqual(persistence.records.map(\.detail), ["tel"])
    }

    func testStoredRecordWithoutADetailStillDecodesAfterSchemeScoping() throws {
        let recordID = UUID()
        let spaceID = SpaceID()
        let json = """
            [{
              "id":"\(recordID.uuidString)",
              "spaceID":{"rawValue":"\(spaceID.rawValue.uuidString)"},
              "origin":{"scheme":"https","host":"news.example","port":443},
              "permission":"popups",
              "decision":"denyPersistently",
              "modifiedAt":0
            }]
            """

        let records = try JSONDecoder().decode(
            [BrowserSitePermissionRecord].self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(records.first?.permission, .popups)
        XCTAssertNil(records.first?.detail)
        XCTAssertEqual(records.first?.displayLabel, "Pop-ups")
    }

    private func assertCodableRawValue<Value: Codable & Equatable>(
        _ value: Value,
        equals rawValue: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let encoded = try JSONEncoder().encode(value)
        XCTAssertEqual(
            String(decoding: encoded, as: UTF8.self),
            "\"\(rawValue)\"",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try JSONDecoder().decode(Value.self, from: encoded),
            value,
            file: file,
            line: line
        )
    }
}
