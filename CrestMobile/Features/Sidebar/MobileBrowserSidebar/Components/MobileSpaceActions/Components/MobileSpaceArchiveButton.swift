import SwiftUI

struct MobileSpaceArchiveButton: View {
    let mode: MobileBrowserSidebarMode
    let archivedTabCount: Int
    let commonListsAreExpanded: Bool
    let showArchive: () -> Void
    let toggleCommonLists: () -> Void
    let recordCommonListsTriggerFrame: (CGRect) -> Void

    var body: some View {
        Button(
            action: mode == .regularSidebar ? toggleCommonLists : showArchive
        ) {
            MobileSpaceUtilityButtonLabel(systemImage: "archivebox")
        }
        .symbolVariant(
            mode == .regularSidebar && commonListsAreExpanded ? .fill : .none
        )
        .foregroundStyle(.primary)
        .accessibilityLabel(
            mode == .regularSidebar ? "Archive, History, and Downloads" : "Archive"
        )
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier(
            mode == .regularSidebar ? "common-lists-button" : "archive-button"
        )
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            recordCommonListsTriggerFrame(frame)
        }
    }

    private var accessibilityValue: String {
        if mode == .regularSidebar {
            return commonListsAreExpanded ? "Expanded" : "Collapsed"
        }
        return BrowserChromeAccessibility.countValue(
            archivedTabCount,
            singular: "archived tab",
            plural: "archived tabs"
        )
    }
}
