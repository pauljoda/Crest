import SwiftUI

/// App-wide Mac chrome choices. Presentation never changes browsing ownership.
struct BrowserChromeAppearance: Equatable {
    var sidebarOnRight = false
    var borderless = false

    func sidebarEdge(in direction: LayoutDirection) -> HorizontalEdge {
        sidebarOnRight == (direction == .leftToRight) ? .trailing : .leading
    }

    static func contentInsets(for rect: CGRect, in size: CGSize, direction: LayoutDirection) -> EdgeInsets {
        let left = max(0, rect.minX)
        let right = max(0, size.width - rect.maxX)
        return EdgeInsets(
            top: max(0, rect.minY),
            leading: direction == .leftToRight ? left : right,
            bottom: max(0, size.height - rect.maxY),
            trailing: direction == .leftToRight ? right : left
        )
    }

    func pageInsets(docked: Bool, direction: LayoutDirection) -> EdgeInsets {
        guard !borderless else { return EdgeInsets() }
        let edge = sidebarEdge(in: direction)
        return EdgeInsets(
            top: BrowserChromeLayout.pageFrameInset,
            leading: docked && edge == .leading ? 0 : BrowserChromeLayout.pageFrameInset,
            bottom: BrowserChromeLayout.pageFrameInset,
            trailing: docked && edge == .trailing ? 0 : BrowserChromeLayout.pageFrameInset
        )
    }
}

@MainActor
enum BrowserChromeAppearancePreference {
    static let sidebarOnRightKey = "crest.appearance.sidebar-on-right"
    static let borderlessKey = "crest.appearance.borderless"
    static let defaults = defaults(for: .current)

    static func defaults(for environment: BrowserLaunchEnvironment) -> UserDefaults {
        guard BrowserLaunchIsolationPolicy.requiresIsolation(environment) else { return .standard }
        let id = environment.persistentIsolationID ?? "ephemeral-\(UUID().uuidString)"
        return UserDefaults(suiteName: BrowserLaunchIsolationPolicy.isolatedDefaultsSuiteName(isolationID: id))!
    }
}
