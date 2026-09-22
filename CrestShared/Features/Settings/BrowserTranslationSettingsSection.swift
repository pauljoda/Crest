import SwiftUI

struct BrowserTranslationSettingsSection: View {
    @AppStorage(BrowserTranslationPreference.automaticKey, store: BrowserTranslationPreference.defaults)
    private var automaticallyTranslates = false
    @AppStorage(BrowserTranslationPreference.offersKey, store: BrowserTranslationPreference.defaults)
    private var offersTranslation = true
    @AppStorage(BrowserTranslationPreference.rulesKey, store: BrowserTranslationPreference.defaults)
    private var rulesRawValue = ""
    @State private var catalog = BrowserTranslationLanguageCatalog()
    @State private var couldNotOpenLanguages = false
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    private var rules: BrowserAutomaticTranslationRules { .init(rawValue: rulesRawValue) }
    private var sourceIDs: [String] {
        let installed = catalog.installedIDs
        let saved = rules.sources.keys.filter { saved in
            !BrowserAutomaticTranslationRules.matches(saved, in: installed).contains(true)
        }
        return (installed + saved).sorted {
            BrowserTranslationLanguageCatalog.name($0).localizedStandardCompare(
                BrowserTranslationLanguageCatalog.name($1)) == .orderedAscending
        }
    }

    var body: some View {
        Section("Page Translation", systemImage: "character.bubble") {
            Toggle("Offer to Translate", isOn: $offersTranslation)
            Toggle("Automatically Translate", isOn: $automaticallyTranslates)
                .accessibilityIdentifier("automatic-translation-toggle")
            CrestFormFootnote(
                "Translate only the languages you turn on below, using their chosen destination. Other languages stay unchanged. Automatic translation never shows a popup or downloads languages."
            )
            VStack(alignment: .leading, spacing: 0) {
                if !sourceIDs.isEmpty {
                    ForEach(sourceIDs, id: \.self) { source in
                        languageRow(source)
                            .padding(.vertical, 12)
                        if source != sourceIDs.last { Divider() }
                    }
                } else if catalog.hasChecked {
                    Label("No downloaded language pairs", systemImage: "arrow.down.circle")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                }
                Divider().padding(.vertical, 12)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { languageActions }
                    VStack(alignment: .leading, spacing: 12) { languageActions }
                }
                #if os(macOS)
                    Text(
                        "Add languages in System Settings → General → Language & Region → Translation Languages, then refresh this list."
                    )
                    .crestFormFootnote().padding(.top, 10)
                #else
                    Text("Download both languages in Apple’s Translate app, then refresh this list.")
                        .crestFormFootnote().padding(.top, 10)
                #endif
                if couldNotOpenLanguages {
                    Text(
                        "Could not open language downloads. Open your device’s language settings to manage downloaded translation languages."
                    )
                    .foregroundStyle(.orange).font(.caption).padding(.top, 8)
                }
            }
        }
        .containerValue(\.settingsFullWidth, true)
        .task { await catalog.refresh() }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await catalog.refresh() } }
        }
    }

    @ViewBuilder
    private var languageActions: some View {
        Button {
            Task { await catalog.refresh() }
        } label: {
            Label(catalog.isRefreshing ? "Checking Languages…" : "Refresh Languages", systemImage: "arrow.clockwise")
        }
        .disabled(catalog.isRefreshing)
        .accessibilityIdentifier("refresh-translation-languages")
        #if os(macOS)
            Button("Download Languages…", systemImage: "arrow.up.forward") {
                openLanguages(URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!)
            }
        #else
            Button("Open Translate…", systemImage: "arrow.up.forward") {
                openLanguages(URL(string: "translate://")!)
            }
        #endif
    }

    private func openLanguages(_ url: URL) {
        openURL(url) { accepted in couldNotOpenLanguages = !accepted }
    }

    private func languageRow(_ source: String) -> some View {
        let targets = catalog.targets(for: source)
        let saved = rules.rule(for: source)
        let preferred = Locale.preferredLanguages.first ?? "en"
        let target =
            saved?.targetID
            ?? zip(targets, BrowserAutomaticTranslationRules.matches(preferred, in: targets)).first { $0.1 }?.0 ?? ""
        let enabled = saved?.isEnabled ?? false
        let available = targets.contains(target)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) {
                languageToggle(source, target: target, enabled: enabled, available: available)
                destinationPicker(source, target: target, targets: targets, enabled: enabled)
                    .frame(width: 300)
            }
            VStack(alignment: .leading, spacing: 10) {
                languageToggle(source, target: target, enabled: enabled, available: available)
                destinationPicker(source, target: target, targets: targets, enabled: enabled)
            }
        }
        .disabled(!automaticallyTranslates)
        .opacity(automaticallyTranslates ? 1 : 0.45)
    }

    private func languageToggle(_ source: String, target: String, enabled: Bool, available: Bool) -> some View {
        Toggle(
            isOn: Binding(
                get: { enabled },
                set: { save(source, target: target, enabled: $0) }
            )
        ) {
            VStack(alignment: .leading, spacing: 4) {
                Text(BrowserTranslationLanguageCatalog.name(source))
                if !target.isEmpty && !available && catalog.hasChecked {
                    Text("Download both languages to use this mapping")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .disabled(!enabled && !available)
        .accessibilityIdentifier("automatic-translation-source-\(source)")
    }

    private func destinationPicker(_ source: String, target: String, targets: [String], enabled: Bool) -> some View {
        Picker(
            "Translate to",
            selection: Binding(
                get: { target }, set: { save(source, target: $0, enabled: enabled) }
            )
        ) {
            if target.isEmpty { Text("Choose Language").tag("") }
            if !target.isEmpty && !targets.contains(target) {
                Text("\(BrowserTranslationLanguageCatalog.name(target)) — Not Downloaded").tag(target)
            }
            ForEach(targets, id: \.self) { id in
                Text(BrowserTranslationLanguageCatalog.name(id)).tag(id)
            }
        }
        .pickerStyle(.menu)
        .disabled(targets.isEmpty)
        .accessibilityLabel("Translate \(BrowserTranslationLanguageCatalog.name(source)) to")
    }

    private func save(_ source: String, target: String, enabled: Bool) {
        var updated = rules
        updated.set(sourceID: source, targetID: target, isEnabled: enabled)
        rulesRawValue = updated.rawValue
    }
}
