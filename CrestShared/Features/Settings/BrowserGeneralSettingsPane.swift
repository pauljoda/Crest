import SwiftUI

/// What Crest does when it opens, and whether the system hands it links.
///
/// Startup was already the same three rows twice, down to the footnote. The default
/// browser section was not, and could not be: the desktop can claim the HTTP and
/// HTTPS handlers directly, while iOS can only send the reader to Default Apps
/// Settings and ask again afterwards. That difference is not styling — it is what
/// each system permits — so it is read from
/// ``BrowserDefaultBrowserController/requestStyle`` rather than from `#if os`, which
/// also makes it the one thing about this pane a test can pin.
///
/// Window transparency stays macOS-only because it is a property of a window Crest
/// draws itself.
struct BrowserGeneralSettingsPane: View {
    let browser: BrowserStore

    @Bindable private var linkPreferences: BrowserLinkPreferenceStore
    @State private var defaultBrowser = BrowserDefaultBrowserController()
    @State private var isCheckingDefaultBrowser = true
    @AppStorage(BrowserTranslationPreference.automaticKey, store: BrowserTranslationPreference.defaults)
    private var automaticallyTranslates = false
    @AppStorage(BrowserStartupPreference.key) private var startupBehaviorRawValue =
        BrowserStartupBehavior.defaultBehavior.rawValue

    init(
        browser: BrowserStore,
        linkPreferences: BrowserLinkPreferenceStore = .shared
    ) {
        self.browser = browser
        _linkPreferences = Bindable(wrappedValue: linkPreferences)
    }

    var body: some View {
        BrowserSettingsPane(.general) {
            Section("Startup") {
                #if os(macOS)
                    Picker("When Crest opens", selection: startupBehavior) {
                        ForEach(BrowserStartupBehavior.allCases) { behavior in
                            Text(behavior.title).tag(behavior)
                        }
                    }
                #endif

                CrestSpaceMenuPicker(
                    "Default Space",
                    selection: browser.defaultSpaceBinding(),
                    spaces: CrestSpaceIdentity.list(browser.session.spaces),
                    accessibilityIdentifier: "default-space-picker"
                )

                CrestFormFootnote(
                    "Startup choices take effect the next time Crest opens a window."
                )
            }

            BrowserNewTabSettingsSection(preferences: linkPreferences)

            BrowserDurableTabSettingsSection(preferences: .shared)

            #if os(macOS)
                BrowserSplitFocusSettingsSection()
            #endif

            Section("Page Translation") {
                Toggle("Automatically Translate", isOn: $automaticallyTranslates)
                    .accessibilityIdentifier("automatic-translation-toggle")
                CrestFormFootnote(
                    "Translate pages into your preferred device language when the required languages are already downloaded. Other pages show a translation offer. Automatic translation never downloads languages."
                )
            }

            #if os(macOS)
                BrowserPictureInPictureSettingsSection()
                BrowserSpellCheckingSettingsSection()
            #endif

            Section("Default browser") {
                HStack(spacing: 12) {
                    defaultBrowserStatus
                    Spacer(minLength: 8)
                    Button {
                        Task { await refreshDefaultBrowserStatus() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 28, height: 28)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.borderless)
                    .help("Check Again")
                    .accessibilityLabel("Check Again")
                    .disabled(isCheckingDefaultBrowser || defaultBrowser.isWorking)
                    .accessibilityIdentifier("check-default-browser-status")
                }
                if case .unavailable(let message) = defaultBrowser.status {
                    Text(message).crestFormFootnote()
                }
                defaultBrowserActions
            }
        }
        .task {
            guard defaultBrowser.status == .unknown else {
                isCheckingDefaultBrowser = false
                return
            }
            await refreshDefaultBrowserStatus()
        }
    }

    // MARK: - Default browser

    /// A status the reader can act on, and the spinner that says Crest is still
    /// finding out. Both shells pin `default-browser-status` on whichever of the two
    /// is showing, because that is the element automation reads the answer from.
    @ViewBuilder
    private var defaultBrowserStatus: some View {
        if isCheckingDefaultBrowser {
            HStack(spacing: CrestSpacing.small) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text("Checking…")
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("default-browser-status")
        } else {
            Label(
                defaultBrowserStatusTitle,
                systemImage: defaultBrowserStatusSymbol
            )
            .foregroundStyle(defaultBrowserStatusStyle)
            .accessibilityIdentifier("default-browser-status")
        }
    }

    @ViewBuilder
    private var defaultBrowserActions: some View {
        switch defaultBrowser.requestStyle {
        case .direct:
            if defaultBrowser.status != .isDefault {
                Button("Set as Default…") {
                    Task { await defaultBrowser.requestDefault() }
                }
                .buttonStyle(.bordered)
                .disabled(defaultBrowser.isWorking)
                .accessibilityIdentifier("make-default-browser")
            }
        case .systemSettings:
            Button("Open Default Apps Settings…", systemImage: "arrow.up.forward") {
                defaultBrowser.openSystemSettings()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("open-default-apps-settings")
        }
    }

    @MainActor
    private func refreshDefaultBrowserStatus() async {
        isCheckingDefaultBrowser = true
        defer { isCheckingDefaultBrowser = false }
        await Task.yield()
        guard !Task.isCancelled else { return }
        defaultBrowser.refreshStatus()
    }

    /// Plain `String`s rather than catalog keys, exactly as both shells wrote them:
    /// these are read out of a `switch` into a `Label`, and one of them arrives from
    /// the system as an error description.
    private var defaultBrowserStatusTitle: String {
        switch defaultBrowser.status {
        case .unknown: "Not checked"
        case .isDefault: "Crest is the default"
        case .notDefault: "Crest is not the default"
        case .unavailable: "Status unavailable"
        }
    }

    private var defaultBrowserStatusSymbol: String {
        switch defaultBrowser.status {
        case .unknown: "circle.dotted"
        case .isDefault: "checkmark.circle.fill"
        case .notDefault: "circle"
        case .unavailable: "exclamationmark.circle"
        }
    }

    private var defaultBrowserStatusStyle: AnyShapeStyle {
        switch defaultBrowser.status {
        case .isDefault: AnyShapeStyle(.green)
        case .unavailable: AnyShapeStyle(.orange)
        default: AnyShapeStyle(.secondary)
        }
    }

    // MARK: - Startup

    private var startupBehavior: Binding<BrowserStartupBehavior> {
        Binding {
            BrowserStartupBehavior(rawValue: startupBehaviorRawValue)
                ?? .defaultBehavior
        } set: { behavior in
            startupBehaviorRawValue = behavior.rawValue
        }
    }
}

struct BrowserNewTabSettingsSection: View {
    static let controlIdentifier =
        "focus-new-tabs-opened-from-links-toggle"

    @Bindable var preferences: BrowserLinkPreferenceStore

    var body: some View {
        Section("Tabs") {
            Toggle(
                "Focus new tabs opened from links",
                isOn: $preferences.focusesNewTabsOpenedFromLinks
            )
            .accessibilityIdentifier(Self.controlIdentifier)

            CrestFormFootnote(
                "Selects tabs opened with Command-click or middle-click when the webpage supports it. Add Shift to reverse this choice. Background tabs load immediately."
            )

            Toggle(
                "Follow tabs moved to another Space",
                isOn: $preferences.followsTabsMovedToAnotherSpace
            )
            .accessibilityIdentifier("follow-tabs-moved-to-another-space-toggle")

            CrestFormFootnote(
                "Switch to the destination Space and open the moved tab. Turn off to keep browsing without following the tab."
            )
        }
    }
}

#if os(macOS)
    /// The one supported app-level override for WebKit's macOS text checker.
    /// WebKit initializes the text checker once per process, so the persisted
    /// preference intentionally advertises its relaunch boundary in the UI.
    struct BrowserSpellCheckingSettingsSection: View {
        static let controlIdentifier = "continuous-spell-checking-toggle"

        @AppStorage(BrowserMacWebTextAssistancePolicy.spellCheckingKey)
        private var isEnabled =
            BrowserMacWebTextAssistancePolicy.defaultIsSpellCheckingEnabled

        var body: some View {
            Section("Typing") {
                Toggle(
                    "Check spelling on webpages",
                    isOn: $isEnabled
                )
                .accessibilityIdentifier(Self.controlIdentifier)

                CrestFormFootnote(
                    "Highlights misspelled words without changing what you type. Changes take effect the next time Crest opens."
                )
            }
        }
    }
#endif
