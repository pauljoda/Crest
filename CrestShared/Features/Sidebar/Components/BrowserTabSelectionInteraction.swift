import SwiftUI

/// Selection uses the live control bounds, not the resting frames frozen by a drag.
struct BrowserTabSelectionTarget: ViewModifier {
    let tabID: TabID?
    let browser: BrowserStore?
    let assignment: BrowserSpaceRuntimeAssignment
    var isEnabled = true
    var folderID: FolderID? = nil

    func body(content: Content) -> some View {
        content.background {
            #if os(macOS)
                if let item = folderID.map(BrowserSelectionItemID.folder) ?? tabID.map(BrowserSelectionItemID.tab),
                    let browser, isEnabled
                {
                    BrowserNativeTabSelectionTarget(itemID: item, browser: browser, assignment: assignment)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            #endif
        }
    }
}

/// Selection belongs to the activation button, never its close control.
struct BrowserTabSelectionAccessibility: ViewModifier {
    let tabID: TabID
    let browser: BrowserStore?
    let isActive: Bool
    let isLoaded: Bool

    private var selected: Bool { browser?.tabMultiSelection.contains(tabID) == true }

    func body(content: Content) -> some View {
        content
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityValue(value)
            #if os(macOS)
                .accessibilityAction(named: selected ? "Remove from Selection" : "Add to Selection") {
                    guard let browser else { return }
                    browser.tabMultiSelection.click(
                        tabID, units: BrowserSidebarSelection.itemUnits(in: browser), command: true)
                }
                .accessibilityAction(named: "Select Range to Here") {
                    guard let browser else { return }
                    browser.tabMultiSelection.click(
                        tabID, units: BrowserSidebarSelection.itemUnits(in: browser), command: true, shift: true)
                }
            #endif
    }

    private var value: String {
        var parts = [BrowserChromeAccessibility.tabValue(isLoaded: isLoaded)]
        if isActive { parts.append(String(localized: "Active page")) }
        if selected { parts.append(String(localized: "Selected for tab actions")) }
        return parts.joined(separator: ", ")
    }
}

struct BrowserFolderSelectionAccessibility: ViewModifier {
    let folderID: FolderID
    let browser: BrowserStore
    private var selected: Bool { browser.tabMultiSelection.contains(.folder(folderID)) }
    func body(content: Content) -> some View {
        content.accessibilityAddTraits(selected ? .isSelected : [])
            #if os(macOS)
                .accessibilityAction(named: selected ? "Remove from Selection" : "Add to Selection") {
                    browser.tabMultiSelection.click(
                        .folder(folderID), units: BrowserSidebarSelection.itemUnits(in: browser), command: true)
                }
                .accessibilityAction(named: "Select Range to Here") {
                    browser.tabMultiSelection.click(
                        .folder(folderID), units: BrowserSidebarSelection.itemUnits(in: browser), command: true,
                        shift: true)
                }
            #endif
    }
}
