import SwiftUI

/// A glyph button in the Space settings toolbar, on Crest's round icon
/// button.
struct BrowserSpaceSettingsIconButton: View {
    let title: LocalizedStringKey
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.crestIcon())
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserSpaceSettingsIconButton(title: "Customize", symbol: "paintpalette", action: {}).padding()
    }
#endif
