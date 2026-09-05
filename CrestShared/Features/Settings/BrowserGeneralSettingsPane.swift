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

    @Bindable private var pageZoomPreferences: BrowserDefaultPageZoomStore
    @Bindable private var linkPreferences: BrowserLinkPreferenceStore
    @State private var defaultBrowser = BrowserDefaultBrowserController()
    @State private var isCheckingDefaultBrowser = true
    @AppStorage(BrowserStartupPreference.key) private var startupBehaviorRawValue =
        BrowserStartupBehavior.defaultBehavior.rawValue
    #if os(iOS)
        @AppStorage(MobileCollapsedSidebarFullscreenPreference.key)
        private var collapsedSidebarFullscreenIsEnabled = false
    #endif

    init(
        browser: BrowserStore,
        pageZoomPreferences: BrowserDefaultPageZoomStore = .shared,
        linkPreferences: BrowserLinkPreferenceStore = .shared
    ) {
        self.browser = browser
        _pageZoomPreferences = Bindable(wrappedValue: pageZoomPreferences)
        _linkPreferences = Bindable(wrappedValue: linkPreferences)
    }

    var body: some View {
        BrowserSettingsPane(.general) {
            Section("Startup") {
                Picker("When Crest opens", selection: startupBehavior) {
                    ForEach(BrowserStartupBehavior.allCases) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                }

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

            BrowserPlatformAppearanceSettingsSection()

            BrowserDefaultPageZoomSettingsSection(
                preferences: pageZoomPreferences
            )

            #if os(macOS)
                BrowserPictureInPictureSettingsSection()
                BrowserSpellCheckingSettingsSection()
            #endif

            #if os(iOS)
                Section("Layout") {
                    Toggle(
                        "Collapsed Sidebar Fullscreen",
                        isOn: $collapsedSidebarFullscreenIsEnabled
                    )
                    .accessibilityIdentifier(
                        "collapsed-sidebar-fullscreen-toggle"
                    )

                    CrestFormFootnote(
                        "Removes the themed border around a single webpage whenever the sidebar is undocked. Split View always keeps its border."
                    )
                }
            #endif

            Section("Default browser") {
                CrestSettingsStatusRow("Status") {
                    defaultBrowserStatus
                }

                if case .unavailable(let message) = defaultBrowser.status {
                    Text(message).crestFormFootnote()
                }

                defaultBrowserActions

                switch defaultBrowser.requestStyle {
                case .direct:
                    CrestFormFootnote(
                        "macOS asks for consent when Crest requests ownership of HTTP and HTTPS links."
                    )
                case .systemSettings:
                    CrestFormFootnote(
                        "Choose Crest in Default Apps Settings, then return here and check the status."
                    )
                }
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

    /// The desktop claims the handler itself and hides the claim once it holds it;
    /// iOS can only open Default Apps Settings, and keeps offering to.
    @ViewBuilder
    private var defaultBrowserActions: some View {
        switch defaultBrowser.requestStyle {
        case .direct:
            if defaultBrowser.status != .isDefault {
                Button(
                    "Make Crest Default Browser",
                    systemImage: "checkmark.circle"
                ) {
                    Task { await defaultBrowser.requestDefault() }
                }
                .buttonStyle(.crestPrimary)
                .disabled(defaultBrowser.isWorking)
                .accessibilityIdentifier("make-default-browser")
            }
        case .systemSettings:
            Button {
                defaultBrowser.openSystemSettings()
            } label: {
                actionRowLabel("Open Default Apps Settings", systemImage: "gear")
            }
            .buttonStyle(.crestTertiary)
            .accessibilityIdentifier("open-default-apps-settings")
        }

        Button {
            Task { await refreshDefaultBrowserStatus() }
        } label: {
            actionRowLabel("Check Again", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.crestTertiary)
        .disabled(isCheckingDefaultBrowser || defaultBrowser.isWorking)
        .accessibilityIdentifier("check-default-browser-status")

        if defaultBrowser.isWorking {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Updating default browser")
        }
    }

    /// A quiet action that occupies its whole row.
    ///
    /// The two default-browser actions are a pair the reader compares, and shipped
    /// automation pins that they are the same width and the same rhythm apart. A
    /// bare `Label` inside `.crestTertiary` would size to its text and break both, so
    /// the label claims the row and the style's hit shape follows it.
    private func actionRowLabel(
        _ title: LocalizedStringKey,
        systemImage: String
    ) -> some View {
        Label(title, systemImage: systemImage)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                "Selects tabs opened with Command-click or middle-click."
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

/// The single adaptive presentation of Crest's global page-zoom baseline.
/// Both platform settings shells route through `BrowserGeneralSettingsPane`, so
/// this native slider and its reset action cannot drift into duplicate controls.
struct BrowserDefaultPageZoomSettingsSection: View {
    static let controlIdentifier = "default-page-zoom-slider"

    @Bindable var preferences: BrowserDefaultPageZoomStore

    var body: some View {
        Section("Page zoom") {
            LabeledContent("Default page zoom") {
                HStack(spacing: CrestFormRowMetrics.contentSpacing) {
                    Slider(
                        value: $preferences.defaultZoomLevelIndex,
                        in:
                            0...Double(
                                BrowserPageZoomPolicy.levels.count - 1
                            ),
                        step: 1
                    )
                    .labelsHidden()
                    .accessibilityLabel("Default page zoom")
                    .accessibilityValue(
                        BrowserPageZoomPolicy.percentageLabel(
                            for: preferences.defaultZoom
                        )
                    )
                    .accessibilityIdentifier(Self.controlIdentifier)

                    Text(
                        BrowserPageZoomPolicy.percentageLabel(
                            for: preferences.defaultZoom
                        )
                    )
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .trailing)
                }
            }

            Button("Reset to 100%") {
                preferences.defaultZoom = BrowserPageZoomPolicy.defaultLevel
            }
            .disabled(
                BrowserPageZoomPolicy.levelsMatch(
                    preferences.defaultZoom,
                    BrowserPageZoomPolicy.defaultLevel
                )
            )

            CrestFormFootnote(
                "Pages using the default update immediately. Page Zoom commands temporarily override it while you navigate; Actual Size returns to this value, and recreated pages start here."
            )
        }
    }
}
