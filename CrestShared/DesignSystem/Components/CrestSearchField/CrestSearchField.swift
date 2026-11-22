import SwiftUI

/// A search: the magnifier, the field, and a control that clears what was
/// typed, on the design system's field surface with its focus ring.
///
/// It is as tall as the shell's input asks, a finger's height wherever touch
/// is available, unless the row it stands in for sets a height of its own.
struct CrestSearchField<Field: View>: View {
    // MARK: - Variables

    @Binding var text: String
    /// Whether the field has the keyboard, where its owner decides that, or
    /// nil for a field that keeps track of it itself.
    let isFocused: FocusState<Bool>.Binding?
    /// The height of the row the field stands in for, or nil for the height
    /// the shell's input asks.
    let height: CGFloat?
    let field: Field

    @Environment(\.browserInteractionCapabilities) private var capabilities
    @FocusState private var ownFocus: Bool

    private var focus: FocusState<Bool>.Binding { isFocused ?? $ownFocus }

    // MARK: - Initializers

    /// A search through `field`, such as a field that also takes an emoji.
    init(
        text: Binding<String>,
        isFocused: FocusState<Bool>.Binding? = nil,
        height: CGFloat? = nil,
        @ViewBuilder field: () -> Field
    ) {
        _text = text
        self.isFocused = isFocused
        self.height = height
        self.field = field()
    }

    // MARK: - Actions - Drawing

    var body: some View {
        HStack(spacing: CrestSpacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            field
                .textFieldStyle(.plain)
                .labelsHidden()
                .focused(focus)
            if !text.isEmpty {
                clearControl
            }
        }
        .crestFieldSurface(isFocused: focus.wrappedValue, minHeight: height ?? densityHeight)
    }

    /// The control that empties the field: a small circle, whose presses
    /// reach a finger's width into the field's margin where touch is
    /// available, so the glyph sits where it does under a pointer.
    private var clearControl: some View {
        let outset = capabilities.supportsTouch ? CrestFieldMetrics.clearControlTouchOutset : 0
        return Button {
            text = ""
        } label: {
            Label("Clear Search", systemImage: "xmark.circle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(CrestChromeButtonStyle.circle(diameter: CrestFieldMetrics.clearControlDiameter, hitOutset: outset))
        .padding(.horizontal, -outset)
    }

    private var densityHeight: CGFloat {
        capabilities.supportsTouch ? CrestFieldMetrics.touchSearchHeight : CrestFieldMetrics.pointerSearchHeight
    }
}

extension CrestSearchField where Field == TextField<Text> {
    /// A search through a field of its own, which shows `prompt` until
    /// something is typed.
    init(
        _ prompt: LocalizedStringKey,
        text: Binding<String>,
        isFocused: FocusState<Bool>.Binding? = nil,
        height: CGFloat? = nil
    ) {
        // A grouped form shows a field's title as a label beside it, which
        // left the field to the right of words that looked like its prompt,
        // so the title is the field's own prompt instead.
        self.init(text: text, isFocused: isFocused, height: height) {
            TextField(prompt, text: text, prompt: Text(prompt))
        }
    }
}

#if DEBUG
    #Preview("Pointer and touch") {
        @Previewable @State var query = "crest"
        VStack(spacing: CrestSpacing.large) {
            CrestSearchField("Search Passwords", text: $query)
            CrestSearchField("Search Passwords", text: $query)
                .environment(\.browserInteractionCapabilities, BrowserInteractionCapabilities(supportsTouch: true))
        }
        .padding()
        .frame(width: 360)
    }
#endif
