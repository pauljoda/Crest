import AppKit
import SwiftUI

/// The native Mac quit sheet, using Crest's artwork, typography and controls.
struct BrowserQuitConfirmation: View {
    // MARK: - Variables

    let icon: NSImage
    let cancel: () -> Void
    let quit: () -> Void
    let quitWithoutAskingAgain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.section) {
            VStack(alignment: .leading, spacing: CrestSpacing.extraLarge) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                Text(String(localized: "Quit Crest?"))
                    .font(CrestTypography.display(28))
                    .foregroundStyle(CrestBrandTheme.textDisplay)
                    .accessibilityAddTraits(.isHeader)
            }
            HStack(spacing: CrestSpacing.medium) {
                Button(String(localized: "Quit, and don’t ask again"), action: quitWithoutAskingAgain)
                    .buttonStyle(.crestTertiary)
                Spacer(minLength: CrestSpacing.large)
                Button(action: cancel) {
                    HStack(spacing: CrestSpacing.small) {
                        Text(String(localized: "Cancel"))
                        Text(verbatim: "ESC")
                            .font(CrestTypography.metadata)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.crestSecondary)
                .keyboardShortcut(.cancelAction)
                Button(action: quit) {
                    HStack(spacing: CrestSpacing.small) {
                        Text(String(localized: "Quit"))
                        Image(systemName: "return").accessibilityHidden(true)
                    }
                }
                .buttonStyle(.crestPrimary)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(CrestSpacing.section)
        .frame(width: 580, alignment: .leading)
        .background(CrestBrandTheme.canvas)
    }
}

#if DEBUG
    #Preview("Quit confirmation") {
        BrowserQuitConfirmation(
            icon: NSImage(systemSymbolName: "shield.lefthalf.filled", accessibilityDescription: nil)!,
            cancel: {}, quit: {}, quitWithoutAskingAgain: {})
    }
#endif
