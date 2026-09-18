import SwiftUI

/// Startup, browsing preferences, and the platform's default-browser actions.
struct BrowserGeneralSettingsPane: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    @Bindable private var linkPreferences: BrowserLinkPreferenceStore
    @Environment(\.browserSidebarWidgetRuntime) private var sidebarWidgets
    @State private var defaultBrowser = BrowserDefaultBrowserController()
    @State private var isCheckingDefaultBrowser = true
    @AppStorage(BrowserStartupPreference.key) private var startupBehaviorRawValue =
        BrowserStartupBehavior.defaultBehavior.rawValue

    init(
        browser: BrowserStore,
        spaceAccess: BrowserSpaceAccessController,
        linkPreferences: BrowserLinkPreferenceStore = .shared
    ) {
        self.browser = browser
        self.spaceAccess = spaceAccess
        _linkPreferences = Bindable(wrappedValue: linkPreferences)
    }

    var body: some View {
        BrowserSettingsPane(.general) {
            Section("Startup", systemImage: "power") {
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

            if let sidebarWidgets {
                BrowserSidebarWidgetSettingsSection(runtime: sidebarWidgets)
            }

            #if os(macOS)
                BrowserSplitFocusSettingsSection()
                Section("Link dragging", systemImage: "cursorarrow.motionlines") {
                    Toggle("Drag links to Peek", isOn: $linkPreferences.dragsLinksToPeek)
                        .accessibilityIdentifier("drag-links-to-peek-toggle")
                    CrestFormFootnote(
                        "Drag a link to pull out Peek. Hold Option to drag the link normally. Turn off to reverse these gestures."
                    )
                }
            #endif

            BrowserTranslationSettingsSection()

            #if os(macOS)
                BrowserSystemPermissionSettingsSection(browser: browser, spaceAccess: spaceAccess)
                BrowserPictureInPictureSettingsSection()
                BrowserSpellCheckingSettingsSection()
            #endif

            Section("Default browser", systemImage: "globe") {
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

struct BrowserSidebarWidgetSettingsSection: View {
    let runtime: BrowserSidebarWidgetRuntime

    var body: some View {
        let registrations = runtime.userControllableRegistrations()
        if !registrations.isEmpty {
            Section("Sidebar widgets", systemImage: "rectangle.leftthird.inset.filled") {
                ForEach(registrations) { registration in
                    Toggle(
                        registration.settingsTitle,
                        isOn: enabledBinding(for: registration.id)
                    )
                    .accessibilityIdentifier(
                        "sidebar-widget-\(registration.id.rawValue)-toggle"
                    )
                }

                CrestFormFootnote(
                    "Choose which optional cards appear at the bottom of the sidebar."
                )
            }
        }
    }

    private func enabledBinding(
        for kindID: BrowserSidebarWidgetKindID
    ) -> Binding<Bool> {
        Binding {
            runtime.isWidgetEnabled(kindID)
        } set: { isEnabled in
            runtime.setWidgetEnabled(isEnabled, for: kindID)
        }
    }
}

struct BrowserNewTabSettingsSection: View {
    static let controlIdentifier =
        "focus-new-tabs-opened-from-links-toggle"

    @Bindable var preferences: BrowserLinkPreferenceStore

    var body: some View {
        Section("Tabs", systemImage: "square.stack") {
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
    /// WebKit reads this spelling preference once per process.
    struct BrowserSpellCheckingSettingsSection: View {
        static let controlIdentifier = "continuous-spell-checking-toggle"

        @AppStorage(BrowserMacWebTextAssistancePolicy.spellCheckingKey)
        private var isEnabled =
            BrowserMacWebTextAssistancePolicy.defaultIsSpellCheckingEnabled

        var body: some View {
            Section("Typing", systemImage: "keyboard") {
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
