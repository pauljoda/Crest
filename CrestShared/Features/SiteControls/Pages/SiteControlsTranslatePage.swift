import SwiftUI

/// Translating the page: the languages it translates from and to, the page
/// itself or its original, and the choices that follow the language.
struct SiteControlsTranslatePage: View {
    let model: SiteControlsModel

    @Bindable private var preferences = BrowserAppPreferenceStore.shared

    var body: some View {
        let translation = model.page.translation
        let pickers = BrowserTranslationLanguagePickers(translation: translation)
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            SiteControlsPageSection {
                SiteControlsRowLabel(title: Text("From"), symbol: "text.magnifyingglass") {
                    pickers.sourcePicker.labelsHidden().pickerStyle(.menu).frame(width: 160)
                }
                SiteControlsRowLabel(title: Text("To"), symbol: "translate") {
                    pickers.targetPicker.labelsHidden().pickerStyle(.menu).frame(width: 160)
                }
            }
            SiteControlsPageSection(footer: translation.status.isEmpty ? nil : Text(verbatim: translation.status)) {
                if translation.isWorking {
                    action("Cancel Translation", symbol: "stop.circle") { translation.cancel() }
                } else if translation.isTranslated {
                    action("Show Original", symbol: "arrow.uturn.backward") { translation.showOriginal() }
                } else {
                    action("Translate Page", symbol: "translate") { translation.start() }
                        .disabled(!translation.canTranslate)
                }
            }
            SiteControlsPageSection {
                if !translation.sourceID.isEmpty, BrowserPageTranslation.canTranslateAutomatically {
                    SiteControlsRowLabel(
                        title: Text("Always Translate \(translation.languageName(translation.sourceID))"),
                        symbol: "arrow.triangle.2.circlepath"
                    ) {
                        SiteControlsSwitch(
                            title: Text("Always Translate"),
                            isOn: Binding {
                                preferences.alwaysTranslates(translation)
                            } set: {
                                preferences.setAlwaysTranslates($0, translation)
                            })
                    }
                    .disabled(
                        translation.targetID.isEmpty
                            || BrowserTranslationLanguageCatalog.matches(translation.sourceID, translation.targetID))
                }
                SiteControlsRowLabel(title: Text("Offer to Translate"), symbol: "text.bubble") {
                    SiteControlsSwitch(title: Text("Offer to Translate"), isOn: $preferences.offersTranslation)
                }
            }
            SiteControlsPageSection {
                let toolbar = model.item(.showTranslationControls)
                action(toolbar.title, symbol: toolbar.symbol) { model.run(.showTranslationControls) }
                    .disabled(!toolbar.state.isAvailable)
                action("Download More Languages…", symbol: "arrow.down.circle") { showInformation(translation) }
                action("About Page Translation", symbol: "info.circle") { showInformation(translation) }
            }
        }
        .task { await translation.refreshInstalledLanguages() }
    }

    private func action(
        _ title: LocalizedStringResource, symbol: String, perform: @escaping () -> Void
    ) -> some View {
        SiteControlsRow(title: Text(title), symbol: symbol, titleTint: CrestBrandTheme.accentText, action: perform) {
            EmptyView()
        }
    }

    /// Shows what translation offers on the page, where its information
    /// shows, once Site Controls are away.
    private func showInformation(_ translation: BrowserPageTranslation) {
        model.platform.dismiss()
        translation.showsInformation = true
    }
}
