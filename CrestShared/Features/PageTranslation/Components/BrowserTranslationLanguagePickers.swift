import SwiftUI

struct BrowserTranslationLanguagePickers: View {
    @Bindable var translation: BrowserPageTranslation

    var body: some View {
        sourcePicker
        targetPicker
    }

    var sourcePicker: some View {
        Picker(selection: $translation.sourceID) {
            Label("Detect Language", systemImage: "text.magnifyingglass").tag("")
            // Keep a detected language represented while the supported list loads.
            if !translation.sourceID.isEmpty,
                !translation.languages.contains(where: { $0.minimalIdentifier == translation.sourceID })
            {
                languageLabel(translation.sourceID).tag(translation.sourceID)
            }
            languageChoices
        } label: {
            Label("From", systemImage: "text.magnifyingglass")
        }
        .crestMenuActionLabelStyle()
        .disabled(translation.isWorking)
    }

    var targetPicker: some View {
        Picker(selection: $translation.targetID) {
            if translation.targetID.isEmpty {
                Label("Loading Languages…", systemImage: "clock").tag("")
            } else if !translation.languages.contains(where: { $0.minimalIdentifier == translation.targetID }) {
                languageLabel(translation.targetID).tag(translation.targetID)
            }
            languageChoices
        } label: {
            Label("To", systemImage: "translate")
        }
        .crestMenuActionLabelStyle()
        .disabled(translation.isWorking)
    }

    private func languageLabel(_ identifier: String) -> some View {
        Label {
            Text(translation.languageName(identifier))
        } icon: {
            BrowserTranslationLanguageIcon(identifier: identifier)
        }
        .accessibilityLabel(translation.languageName(identifier))
    }

    @ViewBuilder private var languageChoices: some View {
        if !translation.downloadedLanguages.isEmpty {
            Section("Downloaded") {
                ForEach(translation.downloadedLanguages, id: \.minimalIdentifier) { language in
                    languageLabel(language.minimalIdentifier).tag(language.minimalIdentifier)
                }
            }
        }
        if !translation.otherLanguages.isEmpty {
            Section(
                translation.downloadedLanguages.isEmpty
                    ? String(localized: "Languages") : String(localized: "More Languages")
            ) {
                ForEach(translation.otherLanguages, id: \.minimalIdentifier) { language in
                    languageLabel(language.minimalIdentifier).tag(language.minimalIdentifier)
                }
            }
        }
    }
}
