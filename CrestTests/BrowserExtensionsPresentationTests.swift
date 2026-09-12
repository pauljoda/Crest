import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionsPresentationTests: XCTestCase {

    func testRuntimeReportSeparatesRecoverableDiagnosticsFromHardFailures() {
        let scriptDiagnostic = NSError(
            domain: WKWebExtensionContext.errorDomain,
            code: 7,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "[Messaging] (background/background.js:5:193047)"
            ]
        )
        let manifestDiagnostic = NSError(
            domain: WKWebExtension.errorDomain,
            code: WKWebExtension.Error.invalidManifestEntry.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Empty or invalid command in the commands manifest entry."
            ]
        )
        let backgroundFailure = NSError(
            domain: WKWebExtensionContext.errorDomain,
            code: WKWebExtensionContext.Error
                .backgroundContentFailedToLoad.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "The extension background content failed to load."
            ]
        )
        let missingResource = NSError(
            domain: WKWebExtension.errorDomain,
            code: WKWebExtension.Error.resourceNotFound.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "The extension resource could not be found."
            ]
        )

        let report = BrowserExtensionRuntimeReport(
            errors: [
                scriptDiagnostic,
                manifestDiagnostic,
                backgroundFailure,
                missingResource,
            ]
        )

        XCTAssertEqual(
            report.diagnostics,
            [
                "Empty or invalid command in the commands manifest entry.",
                "[Messaging] (background/background.js:5:193047)",
            ]
        )
        XCTAssertEqual(
            report.errors,
            [
                "The extension background content failed to load.",
                "The extension resource could not be found.",
            ]
        )
    }

    func testRemovalIntentLivesInTheExtensionsModel() throws {
        let space = try XCTUnwrap(BrowserSession.preview.spaces.first)
        let summary = makeSummary(
            requestedPermissions: [],
            requestedHosts: [],
            isEnabled: true,
            isLoaded: false
        )
        let model = BrowserExtensionsModel(
            space: space,
            extensionControllerPool: BrowserExtensionControllerPool()
        )

        model.requestRemoval(of: summary)
        XCTAssertEqual(model.pendingRemoval, summary)

        model.cancelRemoval()
        XCTAssertNil(model.pendingRemoval)
    }

    func testPlatformOptionsActionCarriesExactExtensionAndSpaceIdentity() {
        let spaceID = SpaceID()
        var receivedExtensionID: String?
        var receivedSpaceID: SpaceID?
        let actions = BrowserExtensionPlatformActions {
            receivedExtensionID = $0
            receivedSpaceID = $1
        }

        actions.openOptionsPage(
            extensionID: "extension-a",
            in: spaceID
        )

        XCTAssertTrue(actions.supportsOptionsPage)
        XCTAssertEqual(receivedExtensionID, "extension-a")
        XCTAssertEqual(receivedSpaceID, spaceID)
        XCTAssertFalse(BrowserExtensionPlatformActions.none.supportsOptionsPage)
    }

    func testAccessDecisionRawValuesStayStableWhileCopyLivesInPresentation() {
        XCTAssertEqual(
            BrowserExtensionAccessDecision.allCases.map(\.rawValue),
            ["ask", "allow", "block"]
        )
        XCTAssertEqual(
            BrowserExtensionAccessDecision.allCases.map {
                String(localized: $0.title)
            },
            ["Ask", "Allow", "Block"]
        )
    }

    func testReviewedInstallGrantsOnlyTheRequiredAccessShownToTheUser() {
        let snapshot =
            BrowserExtensionInstallationPermissionPolicy
            .reviewedRequiredAccess(
                permissions: ["storage", "tabs"],
                hosts: ["<all_urls>"]
            )

        XCTAssertEqual(
            Set(snapshot.grantedPermissions.keys),
            ["storage", "tabs"]
        )
        XCTAssertEqual(
            Set(snapshot.grantedHosts.keys),
            ["<all_urls>"]
        )
        XCTAssertTrue(snapshot.deniedPermissions.isEmpty)
        XCTAssertTrue(snapshot.deniedHosts.isEmpty)
        XCTAssertFalse(snapshot.hasRequestedOptionalAccessToAllHosts)
    }

    private func makeSummary(
        requestedPermissions: [String],
        requestedHosts: [String],
        isEnabled: Bool,
        isLoaded: Bool,
        errors: [String] = [],
        diagnostics: [String] = [],
        compatibilitySource: BrowserExtensionCompatibilitySource =
            .chromeWebStore,
        compatibilityAssessment: BrowserExtensionCompatibilityAssessment =
            .compatible
    ) -> BrowserExtensionSummary {
        BrowserExtensionSummary(
            id: "test-extension",
            displayName: "Test Extension",
            version: "1.0",
            requestedPermissions: requestedPermissions,
            requestedHosts: requestedHosts,
            unsupportedAPIs: [],
            errors: errors,
            diagnostics: diagnostics,
            isEnabled: isEnabled,
            isLoaded: isLoaded,
            permissionSnapshot: .empty,
            compatibilitySource: compatibilitySource,
            compatibilityAssessment: compatibilityAssessment
        )
    }
}
