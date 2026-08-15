import Foundation
import XCTest

@testable import Crest

final class BrowserAccessibilityIDTests: XCTestCase {
    func testFeatureIdentifiersUseStableDomainIdentity() throws {
        let spaceID = SpaceID(
            rawValue: try XCTUnwrap(
                UUID(uuidString: "1C5F126A-6A34-47B8-B99D-DC5D06A2C483")
            )
        )
        let tabID = TabID(
            rawValue: try XCTUnwrap(
                UUID(uuidString: "6B701A67-E4B5-4C8D-A195-7B14D3525C2B")
            )
        )
        let windowID = BrowserWindowID(
            rawValue: try XCTUnwrap(
                UUID(uuidString: "DCBDA7AB-F45A-4C4E-B94C-E4A9028EA7A5")
            )
        )

        XCTAssertEqual(
            BrowserSpaceAccessibilityID.sidebar(spaceID),
            "space-sidebar-1c5f126a-6a34-47b8-b99d-dc5d06a2c483"
        )
        XCTAssertEqual(
            BrowserSpaceAccessibilityID.tabs(spaceID),
            "space-tabs-1c5f126a-6a34-47b8-b99d-dc5d06a2c483"
        )
        XCTAssertEqual(
            BrowserTabAccessibilityID.row(tabID),
            "tab-6b701a67-e4b5-4c8d-a195-7b14d3525c2b"
        )
        XCTAssertEqual(
            BrowserTabAccessibilityID.archivedRow(tabID),
            "archived-tab-6b701a67-e4b5-4c8d-a195-7b14d3525c2b"
        )
        XCTAssertEqual(
            BrowserWindowAccessibilityID.scene(windowID),
            "browser-window-dcbda7ab-f45a-4c4e-b94c-e4a9028ea7a5"
        )
    }

    func testManualSetupIdentifiersAreStableAndDoNotUseDisplayText() throws {
        let tabID = TabID(
            rawValue: try XCTUnwrap(
                UUID(uuidString: "6B701A67-E4B5-4C8D-A195-7B14D3525C2B")
            )
        )
        let original = BrowserSetupSiteSuggestion(
            title: "YouTube",
            url: try XCTUnwrap(URL(string: "https://youtube.com")),
            systemImage: "play.rectangle.fill",
            defaultPlacement: .pinned
        )
        let localized = BrowserSetupSiteSuggestion(
            title: "Localized display title",
            url: original.url,
            systemImage: original.systemImage,
            defaultPlacement: original.defaultPlacement
        )

        XCTAssertEqual(
            BrowserManualSetupAccessibilityID.suggestion(original),
            "manual-setup-suggestion-https%3A%2F%2Fyoutube.com"
        )
        XCTAssertEqual(
            BrowserManualSetupAccessibilityID.suggestion(original),
            BrowserManualSetupAccessibilityID.suggestion(localized)
        )
        XCTAssertEqual(
            BrowserManualSetupAccessibilityID.placement(tabID),
            "manual-setup-placement-6b701a67-e4b5-4c8d-a195-7b14d3525c2b"
        )
        assertNonemptyAndUnique(
            BrowserSetupSiteSuggestion.popular.map {
                BrowserManualSetupAccessibilityID.suggestion($0)
            }
        )
    }

    func testSuggestionIdentifiersPreserveFullURLIdentity() throws {
        let googleMail = BrowserSetupSiteSuggestion(
            title: "Mail",
            url: try XCTUnwrap(URL(string: "https://mail.google.com/inbox")),
            systemImage: "envelope",
            defaultPlacement: .saved
        )
        let yahooMail = BrowserSetupSiteSuggestion(
            title: "Mail",
            url: try XCTUnwrap(URL(string: "https://mail.yahoo.com/inbox")),
            systemImage: "envelope",
            defaultPlacement: .saved
        )
        let localFile = BrowserSetupSiteSuggestion(
            title: "Local",
            url: URL(fileURLWithPath: "/tmp/crest suggestion"),
            systemImage: "doc",
            defaultPlacement: .saved
        )

        let identifiers = [googleMail, yahooMail, localFile].map {
            BrowserManualSetupAccessibilityID.suggestion($0)
        }

        assertNonemptyAndUnique(identifiers)
        XCTAssertEqual(
            identifiers[0],
            "manual-setup-suggestion-https%3A%2F%2Fmail.google.com%2Finbox"
        )
    }

    func testOnboardingIdentifiersAreNonemptyAndUniqueWithinFeatureSurfaces() throws {
        let firstSpaceID = SpaceID(
            rawValue: try XCTUnwrap(
                UUID(uuidString: "1C5F126A-6A34-47B8-B99D-DC5D06A2C483")
            )
        )
        let secondSpaceID = SpaceID(
            rawValue: try XCTUnwrap(
                UUID(uuidString: "E70475D5-72D5-45D2-8BD1-7E2D29DF3B0F")
            )
        )
        let manualSetupIdentifiers = [
            BrowserManualSetupAccessibilityID.spacePicker,
            BrowserManualSetupAccessibilityID.addSpace,
            BrowserManualSetupAccessibilityID.sidebarPreview,
            BrowserManualSetupAccessibilityID.spaceName(firstSpaceID),
            BrowserManualSetupAccessibilityID.spaceName(secondSpaceID),
            BrowserManualSetupAccessibilityID.error,
            BrowserManualSetupAccessibilityID.address,
            BrowserManualSetupAccessibilityID.addTab,
        ]
        let mobileIdentifiers = [
            BrowserMobileAccessibilityID.progress,
            BrowserMobileAccessibilityID.welcomeContinue,
            BrowserMobileAccessibilityID.featureNext,
            BrowserMobileAccessibilityID.close,
            BrowserMobileAccessibilityID.back,
            BrowserMobileAccessibilityID.manualSetupFinish,
            BrowserMobileAccessibilityID.spacesFeature,
            BrowserMobileAccessibilityID.tabsFeature,
            BrowserMobileAccessibilityID.syncFeatureList,
            BrowserMobileAccessibilityID.macImportContent,
            BrowserMobileAccessibilityID.macImportReviewFeatures,
            BrowserMobileAccessibilityID.spaceCarousel,
            BrowserMobileAccessibilityID.customizationPreview,
            BrowserMobileAccessibilityID.customizationControls,
            BrowserMobileAccessibilityID.spacePreview(firstSpaceID),
            BrowserMobileAccessibilityID.spacePreview(secondSpaceID),
            BrowserMobileAccessibilityID.removeSpace(firstSpaceID),
            BrowserMobileAccessibilityID.removeSpace(secondSpaceID),
            BrowserMobileAccessibilityID.customizeSpace(firstSpaceID),
            BrowserMobileAccessibilityID.customizeSpace(secondSpaceID),
        ]

        assertNonemptyAndUnique(manualSetupIdentifiers)
        assertNonemptyAndUnique(mobileIdentifiers)
        XCTAssertNotEqual(
            BrowserMobileAccessibilityID.syncFeatureList,
            BrowserMobileAccessibilityID.macImportContent
        )
    }

    private func assertNonemptyAndUnique(
        _ identifiers: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            identifiers.allSatisfy { !$0.isEmpty },
            "Accessibility identifiers must not be empty",
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(identifiers).count,
            identifiers.count,
            "Accessibility identifiers must be unique within a feature surface",
            file: file,
            line: line
        )
    }
}
