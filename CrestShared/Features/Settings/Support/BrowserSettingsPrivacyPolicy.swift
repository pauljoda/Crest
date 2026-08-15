import Foundation

@MainActor
enum BrowserSettingsPrivacyPolicy {
    static func canRevealSpaceData(
        in space: BrowserSpace?,
        accessController: BrowserSpaceAccessController
    ) -> Bool {
        guard let space else { return false }
        return !accessController.isLocked(space)
    }

    static func lockedSpaces(
        in spaces: [BrowserSpace],
        accessController: BrowserSpaceAccessController
    ) -> [BrowserSpace] {
        spaces.filter(accessController.isLocked)
    }

    static func lockedRouteDestinationSpaces(
        for routes: [BrowserLinkRoute],
        in spaces: [BrowserSpace],
        accessController: BrowserSpaceAccessController
    ) -> [BrowserSpace] {
        let destinationIDs = Set(routes.map(\.destinationSpaceID))
        return spaces.filter {
            destinationIDs.contains($0.id) && accessController.isLocked($0)
        }
    }

    static func spacePickerSummary(
        for space: BrowserSpace,
        isDefault: Bool,
        accessController: BrowserSpaceAccessController
    ) -> String {
        var details: [String] = []
        if isDefault {
            details.append(String(localized: "Default"))
        }
        if space.accessPolicy.requiresAuthentication {
            details.append(String(localized: "Private"))
        }
        if !accessController.isLocked(space) {
            let count = space.tabs.count
            details.append(count == 1 ? "1 tab" : "\(count) tabs")
        }
        return details.joined(separator: " · ")
    }
}
