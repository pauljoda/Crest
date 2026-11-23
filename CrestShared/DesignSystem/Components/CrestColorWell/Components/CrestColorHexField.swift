import SwiftUI

/// One color's hex code, which a person can type or paste. It follows the
/// color until the person types, gives the color a full six-digit code as
/// soon as it is typed, and a short one once the person presses Return or
/// leaves the field. A code it can't read puts the color's own back.
struct CrestColorHexField: View {
    // MARK: - Variables

    let color: BrandColor
    /// Whether the person is typing in the field, for a popover that makes
    /// room for it while they do.
    @Binding var isEditing: Bool
    /// Gives the color the code typed.
    let set: (BrandColor) -> Void

    @State private var text = ""
    /// The code the field last showed for the color, which `text` still
    /// equals until the person types.
    @State private var shown = ""
    @FocusState private var isFocused: Bool

    // MARK: - Actions - Drawing

    var body: some View {
        TextField("Hex code", text: $text, prompt: Text(verbatim: "#RRGGBB"))
            .labelsHidden()
            .textFieldStyle(.plain)
            .font(.body.monospaced())
            .autocorrectionDisabled()
            #if os(iOS)
                .textInputAutocapitalization(.characters)
                .keyboardType(.asciiCapable)
            #endif
            .focused($isFocused)
            // Return finishes the code, which leaving the field commits.
            .onSubmit { isFocused = false }
            .crestFieldSurface(isFocused: isFocused, minHeight: CrestColorPopoverMetrics.control.height)
            .frame(width: CrestColorHexFieldMetrics.width)
            .onAppear { show(color.hexCode) }
            // The color moved elsewhere, on the wheel or another handle: the
            // field follows it unless the person is partway through a code.
            .onChange(of: color.hexCode) { _, code in
                if text == shown { show(code) }
            }
            .onChange(of: text) { _, typed in
                // A full code takes at once, so nothing typed is lost when
                // the popover closes; a short one could still be the start
                // of a full one.
                guard typed != shown, Self.isFullCode(typed), let color = BrandColor(hexCode: typed) else { return }
                shown = typed
                if color.hexCode != self.color.hexCode { set(color) }
            }
            .onChange(of: isFocused) { _, focused in
                isEditing = focused
                if !focused { commit() }
            }
            .accessibilityLabel(Text("Hex code"))
            .accessibilityIdentifier("crest-color-hex")
    }

    // MARK: - Actions - Codes

    /// Whether `text` holds all six digits of a code.
    private static func isFullCode(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).filter(\.isHexDigit).count == 6
    }

    // MARK: - Mutators

    /// Shows `code` as the color's.
    private func show(_ code: String) {
        shown = code
        text = code
    }

    /// Gives the color the code typed, then shows the color's own code: the
    /// code typed, tidied, or the one it had when the code spells no color.
    private func commit() {
        guard text != shown else { return }
        if let typed = BrandColor(hexCode: text), typed.hexCode != color.hexCode { set(typed) }
        show(BrandColor(hexCode: text)?.hexCode ?? color.hexCode)
    }
}

enum CrestColorHexFieldMetrics {
    /// Room for a number sign and six digits, with the field's padding.
    static let width: CGFloat = 116
}
