import Foundation
import SwiftUI

enum BrowserImportPreviewControls {
    static let sourceFooterLeadingSymbol: String? = nil
    static let usesAnchoredImportFooter = true
    static let describesDestinationAsSimplifiedBrandingPreview = true
}

enum BrowserImportReviewNavigation {
    static func nextSpaceID(
        after currentID: SpaceID?,
        in spaceIDs: [SpaceID]
    ) -> SpaceID? {
        guard !spaceIDs.isEmpty else { return nil }
        guard let currentID,
            let index = spaceIDs.firstIndex(of: currentID)
        else {
            return spaceIDs.first
        }
        let nextIndex = spaceIDs.index(after: index)
        return nextIndex < spaceIDs.endIndex ? spaceIDs[nextIndex] : nil
    }

    static func isFinalSpace(
        _ currentID: SpaceID?,
        in spaceIDs: [SpaceID]
    ) -> Bool {
        guard let currentID, let last = spaceIDs.last else { return false }
        return currentID == last
    }
}

enum BrowserMacOnboardingPolicy {
    static func nextFirstRunStep(
        after step: BrowserOnboardingStep
    ) -> BrowserOnboardingStep? {
        switch step {
        case .welcome:
            .featureSpaces
        case .featureSpaces:
            .featureTabs
        case .featureTabs:
            .featureSync
        case .featureSync:
            .importBrowser
        case .importBrowser, .review, .manualSetup, .complete:
            nil
        }
    }

    static func destinationAfterImport(
        for _: BrowserOnboardingEntryPoint
    ) -> BrowserOnboardingStep {
        .complete
    }
}

enum BrowserOnboardingAppearancePolicy {
    static func colorSchemeOverride(isManualSetup _: Bool) -> ColorScheme? {
        nil
    }
}

enum BrowserOnboardingLegacyDraftCleanup {
    static let importDraftKey = "crest.onboarding.import-draft"
    static let manualSetupDraftKey = "crest.onboarding.manual-setup-draft"

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: importDraftKey)
        defaults.removeObject(forKey: manualSetupDraftKey)
    }
}

enum BrowserOnboardingSummary {
    static func passwordCount(_ count: Int) -> LocalizedStringResource {
        let count = max(count, 0)
        return LocalizedStringResource(
            "\(count) passwords",
            comment: "Password count shown while reviewing a browser import."
        )
    }

    static func review(
        tabCount: Int,
        passwordCount: Int,
        overflowTabCount: Int
    ) -> LocalizedStringResource {
        let tabs = max(tabCount, 0)
        let passwords = max(passwordCount, 0)
        let overflowTabs = max(overflowTabCount, 0)

        switch (passwords == 0, overflowTabs == 0) {
        case (true, true):
            return LocalizedStringResource(
                "\(tabs) tabs selected",
                comment: "Selected tab count in the browser-import review."
            )
        case (false, true):
            return LocalizedStringResource(
                "\(tabs) tabs selected · \(passwords) passwords",
                comment:
                    "Browser-import review summary. The first count is tabs; the second is passwords."
            )
        case (true, false):
            return LocalizedStringResource(
                "\(tabs) tabs selected · \(overflowTabs) pinned tabs move to a saved folder",
                comment:
                    "Browser-import review summary. The first count is selected tabs; the second is pinned tabs that must become saved tabs."
            )
        case (false, false):
            return LocalizedStringResource(
                "\(tabs) tabs selected · \(passwords) passwords · \(overflowTabs) pinned tabs move to a saved folder",
                comment:
                    "Browser-import review summary. Counts are selected tabs, passwords, then pinned tabs that must become saved tabs."
            )
        }
    }

    static func completedManualSetup(
        newSpaceCount: Int,
        addedTabCount: Int
    ) -> LocalizedStringResource {
        let spaces = max(newSpaceCount, 0)
        let tabs = max(addedTabCount, 0)
        if spaces == 0 {
            return LocalizedStringResource(
                "Updated your Spaces and added \(tabs) tabs.",
                comment: "Completion summary after updating existing Spaces."
            )
        }
        return LocalizedStringResource(
            "Created \(spaces) Spaces and added \(tabs) tabs.",
            comment:
                "Completion summary after manual setup. The first count is new Spaces; the second is added tabs."
        )
    }

    static func completedImport(
        tabCount: Int,
        passwordCount: Int,
        spaceCount: Int
    ) -> LocalizedStringResource {
        let tabs = max(tabCount, 0)
        let passwords = max(passwordCount, 0)
        let spaces = max(spaceCount, 0)
        if passwords == 0 {
            return LocalizedStringResource(
                "Imported \(tabs) reviewed tabs across \(spaces) Spaces.",
                comment:
                    "Browser-import completion summary. The first count is imported tabs; the second is destination Spaces."
            )
        }
        return LocalizedStringResource(
            "Imported \(tabs) reviewed tabs and \(passwords) passwords across \(spaces) Spaces.",
            comment:
                "Browser-import completion summary. Counts are imported tabs, imported passwords, then destination Spaces."
        )
    }
}
