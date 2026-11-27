import SwiftUI

/// Startup, browsing preferences, and the platform's default-browser actions.
struct BrowserGeneralSettingsPane: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    @Bindable private var appPreferences = BrowserAppPreferenceStore.shared
    #if os(macOS)
        @Environment(\.browserSettingsTabState) private var tabState
    #endif
    #if os(iOS)
        @Bindable private var appearance = BrowserDeviceAppearanceStore.shared
    #endif

    init(browser: BrowserStore, spaceAccess: BrowserSpaceAccessController) {
        self.browser = browser
        self.spaceAccess = spaceAccess
    }

    var body: some View {
        #if os(macOS)
            ScrollViewReader { proxy in
                form
                    .task(id: tabState?.consumedRouteRevision) {
                        guard let tabState, let section = tabState.requestedSection else { return }
                        // The settings form restores its previous offset when it mounts.
                        await Task.yield()
                        guard !Task.isCancelled, tabState.requestedSection == section else { return }
                        proxy.scrollTo(section, anchor: .top)
                        tabState.requestedSection = nil
                    }
            }
        #else
            form
        #endif
    }

    private var form: some View {
        BrowserSettingsPane(.general) {
            BrowserDefaultBrowserSection()

            Section("Startup") {
                #if os(macOS)
                    Picker("When Crest opens", selection: $appPreferences.startupBehavior) {
                        ForEach(StartupBehavior.settingsOrder, id: \.self) { behavior in
                            Text(behavior.title).tag(behavior)
                        }
                    }
                #else
                    Toggle("Start on new tab", isOn: startsOnNewTab)
                        .accessibilityIdentifier("start-on-new-tab")
                #endif

                CrestSpaceMenuPicker(
                    "Default Space",
                    selection: browser.defaultSpaceBinding(),
                    spaces: CrestSpaceIdentity.list(browser.spaceModels),
                    accessibilityIdentifier: "default-space-picker"
                )
            }

            #if os(iOS)
                Section("Sidebar") {
                    Toggle("Allow floating sidebar", isOn: $appearance.allowsFloatingSidebar)
                        .accessibilityIdentifier("allow-floating-sidebar")
                }
            #endif

            // Whole-page translation preferences, which reach only the pages of
            // an engine with page translation.
            if browser.core.state.offers(.translation) {
                BrowserTranslationSettingsSection()
            }

            #if os(macOS)
                Section {
                    BrowserSpellCheckingToggle()
                } header: {
                    Text("Webpages")
                } footer: {
                    CrestFormFootnote("Spelling changes apply after Crest restarts.")
                }
                BrowserPictureInPictureSettingsSection(previewSpace: pictureInPicturePreviewSpace)
                    .id(BrowserSettingsDestinationRequest.Section.pictureInPicture)
                BrowserDeveloperToolbarSettingsSection()
            #endif
        }
    }

    #if os(macOS)
        private var pictureInPicturePreviewSpace: SpaceModel? {
            if let source = tabState?.pictureInPicturePreviewSpace,
                let space = browser.spaceModel(matching: source), !spaceAccess.isLocked(space)
            {
                return space
            }
            return browser.shownSpace
        }
    #endif

    #if os(iOS)
        // MARK: - Startup

        /// A phone opens on a new tab in the default Space, or on its tab
        /// viewer, which is its Start Page.
        private var startsOnNewTab: Binding<Bool> {
            Binding {
                appPreferences.startupBehavior.opensNewTab
            } set: { startsOnNewTab in
                appPreferences.startupBehavior = startsOnNewTab ? .newTab : .showStartPage
            }
        }
    #endif
}

#if os(macOS)
    /// WebKit reads this spelling preference once per process.
    struct BrowserSpellCheckingToggle: View {
        static let controlIdentifier = "continuous-spell-checking-toggle"

        private let preferences = BrowserAppPreferenceStore.shared

        /// Read while the body evaluates, so the row follows the core's value.
        private var isEnabled: Binding<Bool> {
            let isEnabled = preferences.checksSpelling
            return Binding {
                isEnabled
            } set: {
                preferences.setChecksSpellingForWebKit($0)
            }
        }

        var body: some View {
            Toggle("Check spelling", isOn: isEnabled)
                .accessibilityIdentifier(Self.controlIdentifier)
        }
    }
#endif
