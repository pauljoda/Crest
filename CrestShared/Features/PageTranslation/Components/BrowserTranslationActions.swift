import SwiftUI

struct BrowserTranslationActions: View {
    let translation: BrowserPageTranslation
    @Bindable private var preferences = BrowserAppPreferenceStore.shared

    private var automaticallyTranslatesSource: Binding<Bool> {
        Binding {
            preferences.alwaysTranslates(translation)
        } set: {
            preferences.setAlwaysTranslates($0, translation)
        }
    }

    var body: some View {
        if !translation.status.isEmpty { Text(translation.status) }
        BrowserTranslationLanguagePickers(translation: translation)
            .pickerStyle(.menu)
        if translation.isWorking {
            Button("Cancel Translation", systemImage: "stop.circle", action: { translation.cancel() })
        } else {
            Button(
                translation.isTranslated
                    ? String(localized: "Translate Page Again") : String(localized: "Translate Page"),
                systemImage: "translate", action: translation.start
            )
            .disabled(!translation.canTranslate)
        }
        if translation.isTranslated {
            Button("Show Original", systemImage: "arrow.uturn.backward", action: translation.showOriginal)
        }
        Divider()
        if !translation.sourceID.isEmpty, BrowserPageTranslation.canTranslateAutomatically {
            Toggle(isOn: automaticallyTranslatesSource) {
                Label(
                    "Always Translate \(translation.languageName(translation.sourceID))",
                    systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(
                translation.targetID.isEmpty
                    || BrowserTranslationLanguageCatalog.matches(translation.sourceID, translation.targetID))
        }
        Toggle("Offer to Translate", isOn: $preferences.offersTranslation)
        Button("Download More Languages…", systemImage: "arrow.down.circle") { translation.showsInformation = true }
        Button("About Page Translation", systemImage: "info.circle") { translation.showsInformation = true }
    }
}
