import SwiftUI
import Translation
import WebKit

struct BrowserTranslationHost: ViewModifier {
    @Bindable var translation: BrowserPageTranslation
    let webView: WKWebView
    let isActive: Bool
    let isLoading: Bool
    let isReaderActive: Bool

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(BrowserTranslationPreference.automaticKey, store: BrowserTranslationPreference.defaults)
    private var automaticallyTranslates = false

    private var detectionID: String {
        "\(translation.documentRevision)-\(isActive)-\(isLoading)-\(isReaderActive)-\(scenePhase == .background)-\(automaticallyTranslates)"
    }

    func body(content: Content) -> some View {
        let configuration = translation.configuration
        return
            content
            .task(id: detectionID) {
                translation.setActive(isActive && !isReaderActive && scenePhase != .background, in: webView)
                guard !isLoading, !isReaderActive, isActive else { return }
                await translation.detect(in: webView)
                await translation.automaticallyTranslateIfAvailable(enabled: automaticallyTranslates)
            }
            .task(id: "\(translation.languageStatusID)-\(translation.isOffered)-\(isActive)-\(scenePhase)") {
                guard isActive, translation.isOffered, scenePhase == .active else { return }
                await translation.refreshInstalledLanguages(force: true)
            }
            .translationTask(configuration) { session in
                await translation.run(using: session, configuration: configuration)
            }
            .onDisappear { translation.setActive(false, in: webView) }
            .sheet(isPresented: $translation.showsInformation) {
                BrowserTranslationInformation(translation: translation)
            }
    }
}

private struct BrowserTranslationInformation: View {
    let translation: BrowserPageTranslation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if !translation.status.isEmpty {
                    Section("Status") { Text(translation.status) }
                }
                Section("On-device Translation") {
                    Text(
                        "Apple translates page text on this device. Languages may need to download first; Apple asks before downloading. Downloaded languages are shared with other apps and remain available after Private Browsing ends."
                    )
                    Text(
                        "Automatically Translate is off by default. When enabled, Crest uses your preferred device language and only languages already downloaded. The translation controls show when a page was automatically translated. Show Original keeps that page in its original language until you navigate or reload."
                    )
                    #if os(iOS)
                        Text(
                            "Tap the address bar’s translation button for options, or touch and hold it to translate immediately."
                        )
                    #endif
                }
                Section("Download Languages") {
                    Text(
                        "Languages confirmed as downloaded appear first. Other choices may need a download; choose a language and tap Translate to let Apple prepare it."
                    )
                    #if os(macOS)
                        Text(
                            "You can also manage languages in System Settings → General → Language & Region → Translation Languages."
                        )
                    #else
                        Text(
                            "You can also download languages in Apple’s Translate app, or manage them in Settings → Apps → Translate → Downloaded Languages."
                        )
                    #endif
                }
                Section("Page Coverage") {
                    Text(
                        "Crest translates page text in place, including headings, links, labels, and buttons. Editable fields, code, embedded pages, and text in images are left unchanged. Translated text may take more space."
                    )
                    Text(
                        "Use Translate Page Again after a page loads new content. Show Original restores text changed by Crest while preserving later website changes and your edits."
                    )
                }
            }
            .navigationTitle("Page Translation")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
            .frame(width: 460, height: 440)
        #else
            .presentationDetents([.medium, .large])
        #endif
    }
}
