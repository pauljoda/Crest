import XCTest

@testable import Crest

final class BrowserLaunchEnvironmentTests: XCTestCase {
    func testParsesEveryOwnedLaunchValueWithoutLosingRawFixtureInputs() {
        let environment = BrowserLaunchEnvironment(
            values: [
                "CREST_ISOLATED_SESSION": "1",
                "CREST_ISOLATED_PERSISTENCE_ID": "APP-252 Verification!",
                "CREST_RESET_SESSION": "1",
                "CREST_SHOWCASE_SESSION": "1",
                "CREST_USE_IN_MEMORY_CREDENTIALS": "1",
                "CREST_SHOW_ONBOARDING": "1",
                "CREST_SHOW_SETUP": "1",
                "CREST_FORCE_ONBOARDING_SETUP": "1",
                "CREST_PERFORMANCE_BASE_URL": "http://127.0.0.1:8080/",
                "CREST_PERFORMANCE_TAB_COUNT": "12",
                "CREST_PERFORMANCE_HEAVY_SESSION": "1",
                "CREST_PERFORMANCE_RUN_ID": "run-42",
                "CREST_UPDATE_WIDGET_FIXTURE": "ready:0.5.99:599",
                "CREST_UPDATE_TEST_FEED_URL": "http://127.0.0.1:48151/appcast.xml",
            ],
            isXCTestRuntime: true,
            isSwiftUIPreviewRuntime: true
        )

        XCTAssertTrue(environment.explicitlyRequiresIsolation)
        XCTAssertEqual(environment.persistentIsolationID, "app-252verification")
        XCTAssertTrue(environment.resetsSession)
        XCTAssertTrue(environment.presentsShowcaseSession)
        XCTAssertTrue(environment.usesInMemoryCredentialVault)
        XCTAssertTrue(environment.forcesOnboardingWelcome)
        XCTAssertTrue(environment.forcesMacOnboardingSetup)
        XCTAssertTrue(environment.forcesMobileOnboardingSetup)
        XCTAssertEqual(
            environment.performanceBaseURLString,
            "http://127.0.0.1:8080/"
        )
        XCTAssertEqual(environment.performanceTabCount, "12")
        XCTAssertTrue(environment.performanceHeavySession)
        XCTAssertEqual(environment.performanceRunID, "run-42")
        XCTAssertEqual(
            environment.softwareUpdateWidgetFixture,
            "ready:0.5.99:599"
        )
        XCTAssertEqual(
            environment.isolatedSoftwareUpdateFeedURL?.absoluteString,
            "http://127.0.0.1:48151/appcast.xml"
        )
        XCTAssertTrue(environment.isXCTestRuntime)
        XCTAssertTrue(environment.isSwiftUIPreviewRuntime)
    }

    func testOnlyTheExactEnabledMarkerTurnsOnLaunchFlags() {
        let environment = BrowserLaunchEnvironment(
            values: [
                "CREST_ISOLATED_SESSION": "true",
                "CREST_RESET_SESSION": "true",
                "CREST_SHOWCASE_SESSION": "01",
                "CREST_USE_IN_MEMORY_CREDENTIALS": "0",
                "CREST_SHOW_ONBOARDING": "YES",
                "CREST_SHOW_SETUP": "",
                "CREST_FORCE_ONBOARDING_SETUP": "false",
            ],
            isXCTestRuntime: false
        )

        XCTAssertFalse(environment.resetsSession)
        XCTAssertFalse(environment.explicitlyRequiresIsolation)
        XCTAssertFalse(environment.presentsShowcaseSession)
        XCTAssertFalse(environment.usesInMemoryCredentialVault)
        XCTAssertFalse(environment.forcesOnboardingWelcome)
        XCTAssertFalse(environment.forcesMacOnboardingSetup)
        XCTAssertFalse(environment.forcesMobileOnboardingSetup)
        XCTAssertNil(environment.persistentIsolationID)
    }

    func testMissingPerformanceRunIDKeepsTheReleaseSoakFallback() {
        let environment = BrowserLaunchEnvironment(
            values: [:],
            isXCTestRuntime: false
        )

        XCTAssertNil(environment.performanceBaseURLString)
        XCTAssertNil(environment.performanceTabCount)
        XCTAssertFalse(environment.performanceHeavySession)
        XCTAssertEqual(environment.performanceRunID, "release-soak")
    }

    func testIsolationPolicyKeepsEveryFixtureAndPerformanceLaunchOutOfUserData() {
        XCTAssertTrue(
            BrowserLaunchIsolationPolicy.requiresIsolation(
                BrowserLaunchEnvironment(values: [:], isXCTestRuntime: true)
            )
        )
        XCTAssertTrue(
            BrowserLaunchIsolationPolicy.requiresIsolation(
                BrowserLaunchEnvironment(
                    values: [
                        "CREST_UPDATE_TEST_FEED_URL":
                            "http://localhost:48151/appcast.xml"
                    ],
                    isXCTestRuntime: false
                )
            )
        )
        XCTAssertTrue(
            BrowserLaunchIsolationPolicy.requiresIsolation(
                BrowserLaunchEnvironment(
                    values: ["CREST_RESET_SESSION": "1"],
                    isXCTestRuntime: false
                )
            )
        )
        XCTAssertTrue(
            BrowserLaunchIsolationPolicy.requiresIsolation(
                BrowserLaunchEnvironment(
                    values: ["CREST_SHOWCASE_SESSION": "1"],
                    isXCTestRuntime: false
                )
            )
        )
        XCTAssertFalse(
            BrowserLaunchIsolationPolicy.requiresIsolation(
                BrowserLaunchEnvironment(values: [:], isXCTestRuntime: false)
            )
        )
        XCTAssertTrue(
            BrowserLaunchIsolationPolicy.requiresIsolation(
                BrowserLaunchEnvironment(
                    values: [
                        "CREST_RESET_SESSION": "1",
                        "CREST_PERFORMANCE_BASE_URL": "",
                    ],
                    isXCTestRuntime: false
                )
            )
        )
        XCTAssertTrue(
            BrowserLaunchIsolationPolicy.requiresIsolation(
                BrowserLaunchEnvironment(
                    values: [
                        "CREST_PERFORMANCE_BASE_URL": "http://127.0.0.1:8080/"
                    ],
                    isXCTestRuntime: false
                )
            )
        )
    }

    func testUpdateTestFeedAcceptsOnlyLoopbackHTTPURLs() {
        let rejectedValues = [
            "https://raw.githubusercontent.com/example/appcast.xml",
            "http://example.com/appcast.xml",
            "file:///tmp/appcast.xml",
        ]

        for value in rejectedValues {
            let environment = BrowserLaunchEnvironment(
                values: ["CREST_UPDATE_TEST_FEED_URL": value],
                isXCTestRuntime: false
            )
            XCTAssertNil(environment.isolatedSoftwareUpdateFeedURL)
        }
    }

    func testOnlyTheXCTestRuntimeSuppressesInstalledApplicationUI() {
        XCTAssertFalse(
            BrowserLaunchIsolationPolicy.presentsInstalledApplicationUI(
                BrowserLaunchEnvironment(values: [:], isXCTestRuntime: true)
            )
        )
        XCTAssertTrue(
            BrowserLaunchIsolationPolicy.presentsInstalledApplicationUI(
                BrowserLaunchEnvironment(
                    values: ["CREST_ISOLATED_SESSION": "1"],
                    isXCTestRuntime: false
                )
            )
        )
        XCTAssertTrue(
            BrowserLaunchIsolationPolicy.presentsInstalledApplicationUI(
                BrowserLaunchEnvironment(
                    values: [:],
                    isXCTestRuntime: false,
                    isSwiftUIPreviewRuntime: true
                )
            )
        )
    }

    func testEveryFixtureLaunchFlagUsesAnIsolatedDataGraph() {
        let keys = [
            "CREST_ISOLATED_SESSION",
            "CREST_RESET_SESSION",
            "CREST_SHOWCASE_SESSION",
            "CREST_USE_IN_MEMORY_CREDENTIALS",
            "CREST_SHOW_ONBOARDING",
            "CREST_SHOW_SETUP",
            "CREST_FORCE_ONBOARDING_SETUP",
        ]

        for key in keys {
            XCTAssertTrue(
                BrowserLaunchIsolationPolicy.requiresIsolation(
                    BrowserLaunchEnvironment(
                        values: [key: "1"],
                        isXCTestRuntime: false
                    )
                ),
                "\(key) must never use the installed app's persistence graph."
            )
        }
    }

    func testSwiftUIPreviewsAlwaysUseTheIsolatedDataGraph() {
        XCTAssertTrue(
            BrowserLaunchIsolationPolicy.requiresIsolation(
                BrowserLaunchEnvironment(
                    values: [:],
                    isXCTestRuntime: false,
                    isSwiftUIPreviewRuntime: true
                )
            )
        )
    }

    /// A named isolated profile persists its WebKit storage, so it has to
    /// persist the record of what is installed as well. An anonymous isolated
    /// launch keeps forgetting both.
    func testOnlyANamedIsolatedProfileKeepsPersistentProfileStorage() {
        let named = BrowserLaunchEnvironment(
            values: [
                "CREST_ISOLATED_SESSION": "1",
                "CREST_ISOLATED_PERSISTENCE_ID": "app-252-verification",
            ],
            isXCTestRuntime: false
        )
        let anonymous = BrowserLaunchEnvironment(
            values: ["CREST_ISOLATED_SESSION": "1"],
            isXCTestRuntime: false
        )

        XCTAssertTrue(BrowserLaunchIsolationPolicy.requiresIsolation(named))
        XCTAssertFalse(
            BrowserLaunchIsolationPolicy.usesEphemeralProfileStorage(named)
        )
        XCTAssertTrue(
            BrowserLaunchIsolationPolicy.usesEphemeralProfileStorage(anonymous)
        )
        XCTAssertEqual(
            BrowserLaunchIsolationPolicy.isolatedDefaultsSuiteName(
                isolationID: "app-252-verification"
            ),
            "\(ProductIdentity.serviceNamespace).isolated.app-252-verification"
        )
        XCTAssertNotEqual(
            BrowserLaunchIsolationPolicy.isolatedDefaultsSuiteName(
                isolationID: "app-252-verification"
            ),
            BrowserLaunchIsolationPolicy.isolatedDefaultsSuiteName(
                isolationID: "app-283-verification"
            )
        )
    }

    /// The extension pool a named isolated launch composes keeps its
    /// installations, so a validation relaunch does not begin by re-adding
    /// every extension while WebKit still holds their storage.
    @MainActor
    func testNamedIsolatedLaunchComposesPersistentExtensionStores() throws {
        let isolationID = "crest-test-\(UInt64.random(in: 0..<1_000_000_000))"
        let suiteName = BrowserLaunchIsolationPolicy.isolatedDefaultsSuiteName(
            isolationID: isolationID
        )
        defer {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(
                forName: suiteName
            )
            var isolatedRoot = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
            isolatedRoot =
                isolatedRoot?
                .appending(path: "Crest", directoryHint: .isDirectory)
                .appending(path: "Isolated", directoryHint: .isDirectory)
                .appending(path: isolationID, directoryHint: .isDirectory)
            if let isolatedRoot {
                try? FileManager.default.removeItem(at: isolatedRoot)
            }
        }
        let spaceID = SpaceID()
        let installed = BrowserExtensionInstallation(
            id: "local.isolated-probe",
            spaceID: spaceID,
            packageName: "isolated-probe-package",
            displayName: "Isolated Probe",
            version: "1.0",
            requestedPermissions: [],
            requestedHosts: [],
            unsupportedAPIs: [],
            errors: [],
            isEnabled: true,
            permissionSnapshot: .empty,
            installedAt: Date(timeIntervalSince1970: 50),
            modifiedAt: Date(timeIntervalSince1970: 100)
        )

        let pool = try XCTUnwrap(
            BrowserExtensionControllerPool.isolated(isolationID: isolationID)
        )
        XCTAssertTrue(pool.persistenceController.upsert(installed))

        let relaunched = try XCTUnwrap(
            BrowserExtensionControllerPool.isolated(isolationID: isolationID)
        )
        XCTAssertEqual(
            relaunched.persistenceController.installations.map(\.id),
            ["local.isolated-probe"]
        )
        // An anonymous isolated launch stays in memory, so the same record
        // must not follow it.
        XCTAssertTrue(
            BrowserExtensionControllerPool().persistenceController
                .installations.isEmpty
        )
    }

    /// A profile name is a directory name too, so anything that could climb
    /// out of the isolated root is refused rather than staged.
    func testIsolatedPackageStoreRefusesAProfileNameThatIsNotAPathComponent() {
        for isolationID in ["", "..", "a/b", "Upper", "space name"] {
            XCTAssertNil(
                BrowserExtensionPackageStore.isolated(
                    isolationID: isolationID
                ),
                "\(isolationID) must not become an isolated package root."
            )
        }
    }

    func testExplicitIsolationAndPerformanceFixturesCannotCancelEachOther() {
        XCTAssertTrue(
            BrowserLaunchIsolationPolicy.requiresIsolation(
                BrowserLaunchEnvironment(
                    values: [
                        "CREST_ISOLATED_SESSION": "1",
                        "CREST_PERFORMANCE_BASE_URL": "http://127.0.0.1:8080/",
                    ],
                    isXCTestRuntime: false
                )
            )
        )
    }

    @MainActor
    func testProductionCompositionRedirectsFixtureInputsToInMemoryOwners() {
        let environments = [
            BrowserLaunchEnvironment(
                values: ["CREST_RESET_SESSION": "1"],
                isXCTestRuntime: false
            ),
            BrowserLaunchEnvironment(
                values: [
                    "CREST_PERFORMANCE_BASE_URL": "http://127.0.0.1:8080/"
                ],
                isXCTestRuntime: false
            ),
        ]

        for environment in environments {
            let store = BrowserStore.production(
                launchEnvironment: environment
            )

            XCTAssertTrue(store.persistence is InMemoryBrowserSessionPersistence)
            XCTAssertTrue(store.credentialVault is InMemoryCredentialVault)
            XCTAssertNotNil(store.syncCoordinator)
        }
    }
}
