import SwiftUI

struct BrowserTranslationMenu: View {
    let translation: BrowserPageTranslation

    var body: some View {
        Menu {
            BrowserTranslationActions(translation: translation)
                .crestMenuActionLabelStyle()
        } label: {
            Image(systemName: "translate")
                .foregroundStyle(translation.isTranslated ? CrestBrandTheme.accent : .primary)
                .overlay(alignment: .topTrailing) {
                    if translation.isWorking {
                        ProgressView().controlSize(.mini).offset(x: 6, y: -5)
                    } else if translation.isTranslated {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, CrestBrandTheme.accent)
                            .offset(x: 6, y: -5)
                            .accessibilityHidden(true)
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .menuOrder(.fixed)
        .accessibilityLabel("Translate Page")
        .accessibilityValue(translation.status)
        .accessibilityAction(named: "Translate Now", translation.start)
        .accessibilityIdentifier("page-translation-menu")
    }
}
