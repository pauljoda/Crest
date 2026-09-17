import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionRegistryTests: XCTestCase {
    func testLegacyUnsignedIdentityIsQuarantinedOnceAndSurvivesReconstruction() throws {
        let spaceID = SpaceID()
        var legacy = installation(
            id: "claimed@crest.test", spaceID: spaceID, packageName: "old.zip",
            permissions: .init(grantedPermissions: ["tabs": .distantFuture]))
        legacy.source = .localPackage(
            .init(extensionID: legacy.id, format: .firefoxXPI, sha256Hex: String(repeating: "a", count: 64)))
        let persistence = InMemoryBrowserExtensionRegistryPersistence(installations: [legacy])
        let registry = BrowserExtensionRegistry(persistence: persistence)
        let migrated = try XCTUnwrap(registry.installations.first)
        XCTAssertNotEqual(migrated.id, legacy.id)
        XCTAssertTrue(migrated.id.hasPrefix("local.xpi."))
        XCTAssertFalse(migrated.isEnabled)
        XCTAssertEqual(migrated.permissionSnapshot, .empty)
        XCTAssertEqual(migrated.packageName, legacy.packageName)
        let before = BrowserExtensionRuntimeIdentifierPolicy.identity(
            extensionID: legacy.id,
            source: .mozillaAddons(
                .init(
                    slug: BrowserMozillaAddonSlug("claimed")!, extensionID: BrowserMozillaExtensionID(legacy.id)!,
                    storeURL: URL(string: "https://addons.mozilla.org/en-US/firefox/addon/claimed/")!, version: "1",
                    xpiSHA256Hex: String(repeating: "a", count: 64))), spaceID: spaceID)
        let after = BrowserExtensionRuntimeIdentifierPolicy.identity(
            extensionID: migrated.id, source: migrated.source, spaceID: spaceID)
        XCTAssertNotEqual(before.baseURL, after.baseURL)
        XCTAssertNotEqual(before.uniqueIdentifier, after.uniqueIdentifier)
        XCTAssertEqual(BrowserExtensionRegistry(persistence: persistence).installations, [migrated])
        var otherLegacy = legacy
        otherLegacy.id = "other@crest.test"
        otherLegacy.source = .localPackage(
            .init(extensionID: otherLegacy.id, format: .firefoxXPI, sha256Hex: String(repeating: "a", count: 64)))
        let distinct = BrowserExtensionRegistry(
            persistence: InMemoryBrowserExtensionRegistryPersistence(
                installations: [legacy, otherLegacy]))
        XCTAssertEqual(
            distinct.installations.count, 2, "Equal archive bytes do not merge separately installed identities")
        XCTAssertEqual(Set(distinct.installations.map(\.id)).count, 2)
    }

    func testReconstructionPreservesSpaceEnablementAndPermissionState() {
        let persistence = InMemoryBrowserExtensionRegistryPersistence()
        let workID = SpaceID()
        let personalID = SpaceID()
        let expiration = Date(timeIntervalSince1970: 2_000_000_000)
        let workPermissions = BrowserExtensionPermissionSnapshot(
            grantedPermissions: ["storage": expiration],
            deniedPermissions: ["tabs": expiration],
            grantedHosts: ["https://example.com/*": expiration],
            deniedHosts: [:],
            hasRequestedOptionalAccessToAllHosts: true
        )
        let registry = BrowserExtensionRegistry(persistence: persistence)

        registry.upsert(
            installation(
                id: "local.shared",
                spaceID: workID,
                packageName: "work-package",
                permissions: workPermissions
            )
        )
        registry.upsert(
            installation(
                id: "local.shared",
                spaceID: personalID,
                packageName: "personal-package"
            )
        )
        registry.setEnabled(
            false,
            extensionID: "local.shared",
            in: personalID
        )

        let reconstructed = BrowserExtensionRegistry(persistence: persistence)

        XCTAssertEqual(
            reconstructed.installation(
                extensionID: "local.shared",
                in: workID
            )?.permissionSnapshot,
            workPermissions
        )
        XCTAssertEqual(
            reconstructed.installation(
                extensionID: "local.shared",
                in: workID
            )?.isEnabled,
            true
        )
        XCTAssertEqual(
            reconstructed.installation(
                extensionID: "local.shared",
                in: personalID
            )?.isEnabled,
            false
        )
        XCTAssertEqual(reconstructed.installations(in: workID).count, 1)
        XCTAssertEqual(reconstructed.installations(in: personalID).count, 1)
    }

    func testPinnedStatePersistsOnlyInTheOwningSpace() {
        let persistence = InMemoryBrowserExtensionRegistryPersistence()
        let workID = SpaceID()
        let personalID = SpaceID()
        let registry = BrowserExtensionRegistry(persistence: persistence)
        registry.upsert(
            installation(
                id: "local.shared",
                spaceID: workID,
                packageName: "work-package"
            )
        )
        registry.upsert(
            installation(
                id: "local.shared",
                spaceID: personalID,
                packageName: "personal-package"
            )
        )

        registry.setPinned(
            true,
            extensionID: "local.shared",
            in: workID
        )

        let reconstructed = BrowserExtensionRegistry(
            persistence: persistence
        )
        XCTAssertEqual(
            reconstructed.installation(
                extensionID: "local.shared",
                in: workID
            )?.isPinned,
            true
        )
        XCTAssertNotEqual(
            reconstructed.installation(
                extensionID: "local.shared",
                in: personalID
            )?.isPinned,
            true
        )
    }

    func testUnsafeAndDuplicatePersistedRecordsAreRepairedBeforeUse() {
        let spaceID = SpaceID()
        let older = installation(
            id: "local.duplicate",
            spaceID: spaceID,
            packageName: "older",
            modifiedAt: Date(timeIntervalSince1970: 10)
        )
        let newer = installation(
            id: "local.duplicate",
            spaceID: spaceID,
            packageName: "newer",
            modifiedAt: Date(timeIntervalSince1970: 20)
        )
        let unsafe = installation(
            id: "local.unsafe",
            spaceID: spaceID,
            packageName: "../outside"
        )
        let persistence = InMemoryBrowserExtensionRegistryPersistence(
            installations: [older, unsafe, newer]
        )

        let registry = BrowserExtensionRegistry(persistence: persistence)

        XCTAssertEqual(registry.installations(in: spaceID), [newer])
        XCTAssertEqual(persistence.installations, [newer])
    }

    func testLegacyPersistedRecordWithoutSourceMetadataStillLoads() throws {
        struct LegacyInstallation: Codable {
            let id: String
            let spaceID: SpaceID
            let packageName: String
            let displayName: String
            let version: String?
            let requestedPermissions: [String]
            let requestedHosts: [String]
            let unsupportedAPIs: [String]
            let errors: [String]
            let isEnabled: Bool
            let permissionSnapshot: BrowserExtensionPermissionSnapshot
            let installedAt: Date
            let modifiedAt: Date
        }

        let suiteName = "BrowserExtensionRegistryLegacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let spaceID = SpaceID()
        let legacy = LegacyInstallation(
            id: "legacy.extension",
            spaceID: spaceID,
            packageName: "legacy-package",
            displayName: "Legacy Extension",
            version: "1.0",
            requestedPermissions: [],
            requestedHosts: [],
            unsupportedAPIs: [],
            errors: [],
            isEnabled: true,
            permissionSnapshot: .empty,
            installedAt: Date(timeIntervalSince1970: 10),
            modifiedAt: Date(timeIntervalSince1970: 20)
        )
        defaults.set(try JSONEncoder().encode([legacy]), forKey: "extensions")

        let registry = BrowserExtensionRegistry(
            persistence: UserDefaultsBrowserExtensionRegistryPersistence(
                defaults: defaults,
                key: "extensions"
            )
        )

        let restored = try XCTUnwrap(
            registry.installation(
                extensionID: legacy.id,
                in: spaceID
            )
        )
        XCTAssertNil(restored.source)
        XCTAssertEqual(restored.displayName, legacy.displayName)
        XCTAssertTrue(restored.isEnabled)
        XCTAssertNotEqual(restored.isPinned, true)
    }

    func testRemovingOneSpacesRegistryRecordsPreservesAnotherSpace() {
        let persistence = InMemoryBrowserExtensionRegistryPersistence()
        let registry = BrowserExtensionRegistry(persistence: persistence)
        let deletedSpaceID = SpaceID()
        let retainedSpaceID = SpaceID()
        let deleted = installation(
            id: "local.deleted",
            spaceID: deletedSpaceID,
            packageName: "deleted-package"
        )
        let retained = installation(
            id: "local.retained",
            spaceID: retainedSpaceID,
            packageName: "retained-package"
        )
        registry.upsert(deleted)
        registry.upsert(retained)

        registry.removeAll(in: deletedSpaceID)

        XCTAssertTrue(registry.installations(in: deletedSpaceID).isEmpty)
        XCTAssertEqual(registry.installations(in: retainedSpaceID), [retained])
        XCTAssertEqual(persistence.installations, [retained])
    }

    func testSafariWebExtensionSourceRoundTripsWithItsHostAppBookmark() {
        let persistence = InMemoryBrowserExtensionRegistryPersistence()
        let registry = BrowserExtensionRegistry(persistence: persistence)
        let spaceID = SpaceID()
        var record = installation(
            id: "com.example.host.web-extension",
            spaceID: spaceID,
            packageName: "com.example.host.web-extension"
        )
        record.source = .safariWebExtension(
            BrowserSafariWebExtensionSource(
                applicationBookmark: Data([0x01, 0x02, 0x03]),
                applicationBundleIdentifier: "com.example.host",
                extensionBundleIdentifier:
                    "com.example.host.web-extension",
                relativeBundlePath:
                    "Contents/PlugIns/Example Web Extension.appex",
                developerTeamIdentifier: "ABCDE12345"
            )
        )

        XCTAssertTrue(registry.upsert(record))

        let reconstructed = BrowserExtensionRegistry(
            persistence: persistence
        )
        XCTAssertEqual(
            reconstructed.installation(
                extensionID: record.id,
                in: spaceID
            ),
            record
        )
    }

    func testSafariWebExtensionSourceRejectsAPathOutsideItsHostApp() {
        let persistence = InMemoryBrowserExtensionRegistryPersistence()
        let registry = BrowserExtensionRegistry(persistence: persistence)
        let spaceID = SpaceID()
        var record = installation(
            id: "com.example.unsafe",
            spaceID: spaceID,
            packageName: "com.example.unsafe"
        )
        record.source = .safariWebExtension(
            BrowserSafariWebExtensionSource(
                applicationBookmark: Data([0x01]),
                applicationBundleIdentifier: "com.example.host",
                extensionBundleIdentifier: "com.example.unsafe",
                relativeBundlePath: "../Unsafe.appex",
                developerTeamIdentifier: nil
            )
        )

        XCTAssertFalse(registry.upsert(record))
        XCTAssertTrue(registry.installations(in: spaceID).isEmpty)
    }

    func testCommandShortcutOverridePersistsOnlyInOwningSpace() {
        let persistence = InMemoryBrowserExtensionRegistryPersistence()
        let registry = BrowserExtensionRegistry(persistence: persistence)
        let workID = SpaceID()
        let personalID = SpaceID()
        let extensionID = "com.example.commands"
        XCTAssertTrue(
            registry.upsert(
                installation(
                    id: extensionID,
                    spaceID: workID,
                    packageName: extensionID
                )
            )
        )
        XCTAssertTrue(
            registry.upsert(
                installation(
                    id: extensionID,
                    spaceID: personalID,
                    packageName: extensionID
                )
            )
        )
        let shortcut = BrowserShortcut(
            key: .character("g"),
            modifiers: [.command, .option]
        )

        registry.setCommandShortcutOverride(
            .custom(shortcut),
            commandID: "addSite",
            extensionID: extensionID,
            in: workID
        )

        let restored = BrowserExtensionRegistry(persistence: persistence)
        XCTAssertEqual(
            restored.installation(
                extensionID: extensionID,
                in: workID
            )?.commandShortcutOverrides?["addSite"],
            .custom(shortcut)
        )
        XCTAssertNil(
            restored.installation(
                extensionID: extensionID,
                in: personalID
            )?.commandShortcutOverrides?["addSite"]
        )
    }

    /// Unpacked extensions now take a hashed identity, but rows written under
    /// the old `local.<uuid>` form have to keep loading rather than being
    /// repaired away.
    func testLegacyAndHashedUnpackedIdentifiersBothSurviveReconstruction() {
        let persistence = InMemoryBrowserExtensionRegistryPersistence()
        let spaceID = SpaceID()
        let legacyID = "local.\(UUID().uuidString.lowercased())"
        let hashedID = BrowserExtensionUnpackedIdentityPolicy.extensionID(
            for: URL(filePath: "/tmp/crest-unpacked-probe")
        )
        let registry = BrowserExtensionRegistry(persistence: persistence)

        registry.upsert(
            installation(
                id: legacyID,
                spaceID: spaceID,
                packageName: "legacy-package"
            )
        )
        registry.upsert(
            installation(
                id: hashedID,
                spaceID: spaceID,
                packageName: "hashed-package"
            )
        )
        let reconstructed = BrowserExtensionRegistry(persistence: persistence)

        XCTAssertTrue(hashedID.hasPrefix("local."))
        XCTAssertEqual(
            Set(reconstructed.installations(in: spaceID).map(\.id)),
            [legacyID, hashedID]
        )
    }

    /// A named isolated profile files its installations in its own preferences
    /// domain, so relaunching that profile finds them again instead of asking
    /// for every extension to be added by hand.
    func testInjectedDefaultsSuitePersistsInstallationsForAReconstruction()
        throws
    {
        let suiteName =
            "com.pauldavis.crest.tests.registry."
            + UUID().uuidString.lowercased()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let spaceID = SpaceID()
        let otherSuiteName =
            "com.pauldavis.crest.tests.registry."
            + UUID().uuidString.lowercased()
        let otherDefaults = try XCTUnwrap(
            UserDefaults(suiteName: otherSuiteName)
        )
        defer { otherDefaults.removePersistentDomain(forName: otherSuiteName) }

        let registry = BrowserExtensionRegistry.isolated(defaults: defaults)
        registry.upsert(
            installation(
                id: "local.isolated",
                spaceID: spaceID,
                packageName: "isolated-package"
            )
        )

        let relaunched = BrowserExtensionRegistry.isolated(defaults: defaults)
        XCTAssertEqual(
            relaunched.installations(in: spaceID).map(\.id),
            ["local.isolated"]
        )
        XCTAssertEqual(
            relaunched.installation(
                extensionID: "local.isolated",
                in: spaceID
            )?.packageName,
            "isolated-package"
        )
        // A different profile is a different domain: one named launch must
        // never inherit another's extensions, or the installed app's.
        XCTAssertTrue(
            BrowserExtensionRegistry.isolated(defaults: otherDefaults)
                .installations.isEmpty
        )
    }

    private func installation(
        id: String,
        spaceID: SpaceID,
        packageName: String,
        permissions: BrowserExtensionPermissionSnapshot = .empty,
        modifiedAt: Date = Date(timeIntervalSince1970: 100)
    ) -> BrowserExtensionInstallation {
        BrowserExtensionInstallation(
            id: id,
            spaceID: spaceID,
            packageName: packageName,
            displayName: "Space Probe",
            version: "1.0",
            requestedPermissions: ["storage"],
            requestedHosts: ["https://example.com/*"],
            unsupportedAPIs: [],
            errors: [],
            isEnabled: true,
            permissionSnapshot: permissions,
            installedAt: Date(timeIntervalSince1970: 50),
            modifiedAt: modifiedAt
        )
    }
}
