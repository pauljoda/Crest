import SwiftUI

/// A glyph button of the phone's floating toolbar, on Liquid Glass.
struct MobileCompactIconButton: View {
    // MARK: - Variables

    let title: String
    let systemImage: String
    var enabled = true
    /// Whether the button stands on glass of its own, rather than on the
    /// glass of the group it sits in.
    var wearsGlass = true
    let action: () -> Void

    // MARK: - Actions - Drawing

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(CrestGlassButtonStyle(wearsGlass: wearsGlass))
        .disabled(!enabled)
        .accessibilityLabel(title)
    }
}

#if DEBUG
    #Preview("Enabled and disabled") {
        HStack {
            MobileCompactIconButton(title: "New Tab", systemImage: "plus", action: {})
            MobileCompactIconButton(title: "Back", systemImage: "chevron.left", enabled: false, action: {})
        }.padding()
    }
#endif
