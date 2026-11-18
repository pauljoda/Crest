import SwiftUI

/// One Space of the browser setup builds: its name, its Background and
/// Accent, each opening the color popover, palettes to take in one tap, and
/// its icon, a crest started from a house or a plain symbol or emoji. The
/// preview shows every change as it is made. Your Space, the person's first
/// Space, is this page under the step's name.
struct BrowserSetupSpacePage: View {
    // MARK: - Variables

    /// Where the page's edits go, or nil when setup holds no such Space.
    let editor: BrowserSetupSpaceEditor?
    let spaceID: UUID
    /// The page's name, or nil to name it after the Space.
    var title: LocalizedStringResource?

    // MARK: - Actions - Drawing

    var body: some View {
        if let editor {
            Form {
                Section {
                    TextField("Name", text: editor.name)
                        .accessibilityIdentifier("setup-space-name")
                } header: {
                    heading(editor)
                }
                Section("Colors") {
                    BrowserSpaceColorWells(branding: editor.branding)
                        .padding(.vertical, CrestSpacing.small)
                    BrowserSpacePalettePicker(branding: editor.branding)
                }
                Section("Icon") {
                    BrowserSpaceIconPicker(branding: editor.branding, symbol: editor.symbol)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        } else {
            ContentUnavailableView("No Space to Edit", systemImage: "square.grid.2x2")
        }
    }

    @ViewBuilder
    private func heading(_ editor: BrowserSetupSpaceEditor) -> some View {
        if let title {
            BrowserSetupPageHeading(title)
        } else {
            BrowserSetupPageHeading(
                verbatim: editor.name.wrappedValue.isEmpty
                    ? String(localized: "Untitled Space") : editor.name.wrappedValue)
        }
    }
}
