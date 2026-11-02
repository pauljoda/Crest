import AppKit
import SwiftUI

/// A Quick Window's command palette, grown out of its address field: the
/// address stays the input line, the results drop below it, and an address
/// or search the person picks opens in the Quick Window's own page.
struct BrowserQuickWindowCommandPaletteLayer: View {
    // MARK: - Types

    /// Where the Quick Window's address field lies, which the palette grows
    /// out of.
    struct FieldAnchor: PreferenceKey {
        static let defaultValue: Anchor<CGRect>? = nil

        static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
            value = value ?? nextValue()
        }
    }

    // MARK: - Variables

    let model: BrowserQuickWindowModel
    let chrome: BrowserChromeState
    let fieldFrame: CGRect?
    let openBrowserWindow: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    @ViewBuilder
    var body: some View {
        if let mode = chrome.commandPaletteMode, let space = model.spaceModel, fieldFrame != nil {
            BrowserCommandPalette(
                browser: model.browser,
                space: space,
                selectedTabID: nil,
                initialQuery: mode.initialQuery(over: model.address),
                commands: commands,
                isSourceAvailable: { _ in false },
                selectTab: { _, _ in false },
                openURL: { _, _, _ in false },
                dismiss: chrome.dismissCommandPalette,
                presentation: .dropping,
                fieldFrame: fieldFrame,
                destination: BrowserQuickWindowPaletteDestination(
                    model: model, isActive: scenePhase == .active, showTab: showTab),
                readPasteboard: { NSPasteboard.general.string(forType: .string) }
            )
            .id(BrowserCommandPalettePresentationIdentity(mode: mode, space: space, source: nil))
            .transition(.browserCommandPaletteOverlay)
        }
    }

    /// What the palette's other rows do from a Quick Window: a Space moves
    /// the Quick Window there, an archived tab reopens in the browser window,
    /// and an answer is copied. Window commands belong to a browser window,
    /// so the palette offers none.
    private var commands: BrowserCommandPaletteCommandRegistry {
        BrowserCommandPaletteCommandRegistry(
            commands: [],
            perform: { _ in },
            switchSpace: moveToSpace,
            reopenArchivedTab: reopenArchivedTab,
            copy: copy
        )
    }

    // MARK: - Actions - Rows

    /// Shows a tab of the Quick Window's Space in the browser window, as Open
    /// In shows a promoted page there.
    private func showTab(_ target: BrowserTabRuntimeAssignment) -> Bool {
        model.browser.selectSpace(target.spaceID)
        guard model.browser.activateSessionTab(target.tabID, in: target.spaceID) else { return false }
        openBrowserWindow()
        return true
    }

    private func moveToSpace(_ id: UUID) {
        guard let space = model.availableSpaceModels.first(where: { $0.id == id }) else { return }
        model.selectSpace(BrowserSpaceRuntimeAssignment(space: space))
    }

    private func reopenArchivedTab(_ id: UUID) {
        model.browser.restoreArchivedTab(id)
        openBrowserWindow()
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        chrome.showNotice(.copied)
    }
}
