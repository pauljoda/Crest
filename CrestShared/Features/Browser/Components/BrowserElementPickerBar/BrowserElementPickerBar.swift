import SwiftUI

/// The bar a page shows while the person picks something on it to block, as
/// Safari's Hide Distracting Items does: what they picked, on a row of its own
/// so it never truncates, and below it the controls that choose the element
/// around it or inside it, cancel, and block it. It floats over the page in
/// Liquid Glass, as the find bar does.
struct BrowserElementPickerBar: View {
    // MARK: - Types

    private enum Metrics {
        static let maximumWidth: CGFloat = 460
        static let descriptionLines = 4
    }

    // MARK: - Variables

    let picker: BrowserElementPicker

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            description
            controls
        }
        .padding(CrestSpacing.large)
        .frame(maxWidth: Metrics.maximumWidth)
        .glassEffect(.regular, in: .rect(cornerRadius: CrestRadius.panel))
        .onKeyPress(.escape) {
            picker.cancel()
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("element-picker-bar")
    }

    // MARK: - Actions - Rows

    /// What the person picked, as the rule that blocks it names it, or what
    /// to do before they pick.
    @ViewBuilder
    private var description: some View {
        Group {
            if let selector = picker.selector {
                Text(verbatim: selector)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            } else {
                Text(hint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(Metrics.descriptionLines)
        .truncationMode(.middle)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        HStack(spacing: CrestSpacing.small) {
            Button(
                "Choose the Element Around It", systemImage: "arrow.up.left.and.arrow.down.right", action: picker.widen
            )
            .labelStyle(.iconOnly)
            .help("Choose the Element Around It")
            .disabled(!picker.canWiden)
            Button(
                "Choose the Element Inside", systemImage: "arrow.down.right.and.arrow.up.left", action: picker.narrow
            )
            .labelStyle(.iconOnly)
            .help("Choose the Element Inside")
            .disabled(!picker.canNarrow)
            Spacer(minLength: CrestSpacing.small)
            Button("Cancel", role: .cancel, action: picker.cancel)
            Button("Block", action: picker.block)
                .buttonStyle(.glassProminent)
                // The accent the page's outline takes, on every platform.
                .tint(CrestBrandTheme.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(picker.selector == nil)
        }
        .buttonStyle(.glass)
    }

    private var hint: LocalizedStringKey {
        #if os(iOS)
            "Tap what you want to block"
        #else
            "Click what you want to block"
        #endif
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserElementPickerBar(picker: BrowserElementPicker()).padding()
    }
#endif
