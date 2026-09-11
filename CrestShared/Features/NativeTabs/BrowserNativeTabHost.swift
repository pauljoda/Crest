import SwiftUI

/// The content seam used by both single cards and Split View, on every shell.
/// The surrounding layout owns identity, geometry, focus, and placement.
struct BrowserNativeTabHost: View {
    let tab: BrowserTab
    let space: BrowserSpace
    /// The shell's floating controls remain outside native scrolling content.
    var bottomChromeHeight: CGFloat = 0
    @Environment(\.browserSettingsTabContent) private var settingsContent
    @Environment(\.browserNativeTabActions) private var actions

    var body: some View {
        Group {
            if let content = tab.nativeContent {
                switch content.kind {
                case BrowserNativeTabContent.gettingStarted.kind:
                    #if os(macOS)
                        BrowserGettingStartedView { url in
                            actions.openURL(assignment, content, url)
                        }
                    #else
                        BrowserMobileGettingStartedView(showsCompactNavigation: bottomChromeHeight > 0)
                    #endif
                case BrowserNativeTabContent.settings.kind:
                    if let settingsContent {
                        settingsContent.makeView(assignment)
                    } else {
                        ContentUnavailableView("Settings unavailable", systemImage: "gearshape")
                    }
                default:
                    ContentUnavailableView(
                        "This tab needs a newer Crest", systemImage: "square.stack.3d.up",
                        description: Text("Its content is still saved. Update Crest to open it.")
                    )
                }
            }
        }
        .id(assignment)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaPadding(.bottom, bottomChromeHeight)
    }

    private var assignment: BrowserTabRuntimeAssignment {
        BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profile.id)
    }
}

/// Native views can ask the shell to open a website, but cannot borrow a page
/// pool, switch profiles, or navigate whichever tab happens to be focused later.
struct BrowserNativeTabActions {
    var openURL: @MainActor (BrowserTabRuntimeAssignment, BrowserNativeTabContent, URL) -> Void = { _, _, _ in }

    @MainActor
    init(browser: BrowserStore, spaceAccess: BrowserSpaceAccessController, didOpenURL: @escaping @MainActor () -> Void)
    {
        openURL = { source, content, url in
            guard
                let space = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                    matching: BrowserSpaceRuntimeAssignment(spaceID: source.spaceID, profileID: source.profileID),
                    in: browser, accessController: spaceAccess),
                space.tabs.first(where: { $0.id == source.tabID })?.nativeContent == content,
                ["https", "http"].contains(url.scheme?.lowercased() ?? "")
            else { return }
            browser.openNewTab(url: url, in: space.id)
            didOpenURL()
        }
    }

    init() {}
}

private struct BrowserNativeTabActionsKey: EnvironmentKey {
    static let defaultValue = BrowserNativeTabActions()
}

extension EnvironmentValues {
    var browserNativeTabActions: BrowserNativeTabActions {
        get { self[BrowserNativeTabActionsKey.self] }
        set { self[BrowserNativeTabActionsKey.self] = newValue }
    }
}
