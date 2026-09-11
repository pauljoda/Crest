import SwiftUI

/// A persistent, full-size crest beside the editor; the browser sidebar supplies
/// the real context. Narrow panes keep the crest above the scrolling controls.
struct BrowserCrestStudioWorkspace: View {
    @Binding var branding: BrowserSpaceBranding
    @Binding var symbol: String
    @Binding var name: String

    var body: some View {
        GeometryReader { geometry in
            let hasInspector = geometry.size.width >= 780
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if !hasInspector { preview(compact: true) }
                    ScrollView {
                        BrowserSpaceBrandingEditor(
                            branding: $branding, symbol: $symbol, previewName: name,
                            showsPreview: false, editableName: $name
                        )
                        .padding(24)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if hasInspector {
                    preview(compact: false)
                        .frame(width: min(300, geometry.size.width * 0.3))
                        .frame(maxHeight: .infinity, alignment: .center)
                        .background(BrowserSettingsCanvas.card)
                        .overlay(alignment: .leading) { Divider() }
                }
            }
        }
        .background(BrowserSettingsCanvas.background)
        .labeledContentStyle(BrowserSettingsLabeledContentStyle())
    }

    private func preview(compact: Bool) -> some View {
        let layout = compact ? AnyLayout(HStackLayout(spacing: 20)) : AnyLayout(VStackLayout(spacing: 24))
        return layout {
            BrowserCrestStudioMark(branding: branding, symbol: symbol, size: compact ? 100 : 204)
                .frame(maxWidth: compact ? 128 : .infinity)
                .padding(.vertical, compact ? 0 : 24)
                .accessibilityLabel("Crest preview")
            VStack(alignment: compact ? .leading : .center, spacing: 8) {
                Text(name.isEmpty ? String(localized: "Your Space") : name)
                    .font(.title3.weight(.semibold)).lineLimit(2)
                Text("Changes appear live in your sidebar.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(compact ? .leading : .center)
                HStack(spacing: 6) {
                    ForEach(Array(branding.crest.layerColors(spaceColors: branding.colors).enumerated()), id: \.offset)
                    { _, color in
                        Circle().fill(color.color).frame(width: 18, height: 18)
                            .overlay { Circle().strokeBorder(.primary.opacity(0.12)) }
                    }
                }.accessibilityHidden(true)
            }
            if compact { Spacer(minLength: 0) }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(BrowserSettingsCanvas.card)
        .overlay(alignment: .bottom) { if compact { Divider() } }
    }
}

struct BrowserCrestStudioTextField: View {
    let title: LocalizedStringKey
    var symbol = "textformat"
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 18).accessibilityHidden(true)
                TextField(title, text: $text)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 42)
            .background(BrowserSettingsCanvas.background, in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10).strokeBorder(
                    isFocused ? CrestBrandTheme.accent : .primary.opacity(0.12), lineWidth: isFocused ? 2 : 1)
            }
        }
    }
}
