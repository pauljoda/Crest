import SwiftUI

/// Gives a sidebar rename field the keyboard's focus as it appears, and
/// commits the edit when the field loses it.
///
/// The field keeps its focus itself rather than the row or folder around it.
/// A view that holds focus state is drawn again whenever focus anywhere in the
/// window changes, and focus changes each time the sidebar makes or drops a
/// row as it scrolls, so a row that held it was drawn again on almost every
/// frame of a scroll.
struct BrowserSidebarRenameFocus: ViewModifier {
    // MARK: - Variables

    /// Ends the edit as the field loses focus. Each owner checks that its edit
    /// is still the one under way, so an edit already ended stays ended.
    let commit: () -> Void
    /// Runs as the field takes focus.
    var focused: () -> Void = {}

    @FocusState private var isFocused: Bool

    // MARK: - Actions - Focus

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .onAppear {
                // The field joins the window on the next pass, which is when
                // it can take the focus.
                Task { @MainActor in isFocused = true }
            }
            .onChange(of: isFocused) { _, isFocused in
                if isFocused { focused() } else { commit() }
            }
    }
}

extension View {
    /// Focuses this rename field as it appears and commits with `commit` when
    /// it loses focus. See `BrowserSidebarRenameFocus`.
    func browserSidebarRenameFocus(commit: @escaping () -> Void, focused: @escaping () -> Void = {}) -> some View {
        modifier(BrowserSidebarRenameFocus(commit: commit, focused: focused))
    }
}
