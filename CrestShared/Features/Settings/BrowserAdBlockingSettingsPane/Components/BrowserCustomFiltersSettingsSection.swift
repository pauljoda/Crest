import SwiftUI

/// The person's own filters, one rule per line in the lists' syntax, which
/// also holds the rules Block Element adds. Edits wait for Save, so a half
/// typed rule never applies.
struct BrowserCustomFiltersSettingsSection: View {
    let core: CrestCore

    @State private var draft: String?
    @State private var saveError: String?

    var body: some View {
        // Read here, so the editor shows the filters again once the core keeps
        // what the person saved.
        let saved = core.state.filterLists.customFilters
        Section {
            TextEditor(text: text(saved: saved))
                .font(.system(.callout, design: .monospaced))
                .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                // Long filters scroll inside the editor, so the page lays out
                // only what shows.
                .frame(minHeight: 120, maxHeight: 360)
                .overlay(alignment: .topLeading) {
                    // An example rule while the editor is empty.
                    Text(verbatim: "example.com##.banner\n||ads.example.com^")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .opacity((draft ?? saved).isEmpty ? 1 : 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .accessibilityLabel("My Filters")
                .accessibilityIdentifier("ad-blocking-my-filters")
            HStack {
                if let saveError {
                    Text(saveError)
                        .font(CrestTypography.metadata)
                        .foregroundStyle(CrestColor.textSecondary)
                }
                Spacer()
                Button("Revert") {
                    draft = nil
                    saveError = nil
                }
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
            .disabled(draft == nil)
        } header: {
            Text("My Filters")
        } footer: {
            Text("One rule per line, as filter lists write them. Block Element adds its rules here.")
        }
    }

    private func text(saved: String) -> Binding<String> {
        Binding {
            draft ?? saved
        } set: { text in
            // The editor hands back its own string, which Swift compares a
            // character at a time, and SwiftUI compares this binding on every
            // keystroke. A native copy compares byte by byte.
            var text = text
            text.makeContiguousUTF8()
            draft = text == saved ? nil : text
        }
    }

    private func save() {
        guard let draft else { return }
        do {
            _ = try core.send(SetCustomFilters(text: draft))
            self.draft = nil
            saveError = nil
        } catch {
            saveError = String(localized: "These filters are too long to keep.")
        }
    }
}
