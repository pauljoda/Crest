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
    /// The Space as its icon shows it, large above its name, for a page with
    /// no preview beside it to show it.
    var icon: BrowserSpaceIdentity?
    /// Shows the Space as Crest will, beside its icon, for a page with no
    /// preview beside it.
    var preview: (() -> Void)?

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
                .browserSetupRaisedRows()
                Section {
                    BrowserSpaceColorWells(branding: editor.branding)
                        .padding(.vertical, CrestSpacing.small)
                    BrowserSpacePalettePicker(branding: editor.branding)
                } header: {
                    CrestSettingsSectionHeading(title: "Colors")
                }
                .browserSetupRaisedRows()
                Section {
                    BrowserSpaceIconPicker(branding: editor.branding, symbol: editor.symbol)
                } header: {
                    CrestSettingsSectionHeading(title: "Icon")
                }
                .browserSetupRaisedRows()
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        } else {
            ContentUnavailableView("No Space to Edit", systemImage: "square.grid.2x2")
        }
    }

    @ViewBuilder
    private func heading(_ editor: BrowserSetupSpaceEditor) -> some View {
        if let icon {
            VStack(alignment: .leading, spacing: CrestSpacing.medium) {
                HStack(alignment: .center) {
                    BrowserSpaceIdentityIcon(identity: icon, size: BrowserSetupSpacePageMetrics.iconSize)
                    Spacer(minLength: CrestSpacing.small)
                    if let preview {
                        Button("Preview", systemImage: "eye", action: preview)
                            .buttonStyle(.crestSecondary)
                            .accessibilityIdentifier("setup-preview")
                    }
                }
                name(editor)
            }
        } else {
            name(editor)
        }
    }

    /// The page's name over the Space's name field.
    @ViewBuilder
    private func name(_ editor: BrowserSetupSpaceEditor) -> some View {
        if let title {
            BrowserSetupPageHeading(title)
        } else {
            BrowserSetupPageHeading(
                verbatim: editor.name.wrappedValue.isEmpty
                    ? String(localized: "Untitled Space") : editor.name.wrappedValue)
        }
    }
}

enum BrowserSetupSpacePageMetrics {
    static let iconSize: CGFloat = 76
}
