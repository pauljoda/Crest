import SwiftUI

/// How new, pinned and saved tabs behave, Split View focus, switching between
/// recent tabs, and the sidebar's optional widgets.
struct BrowserTabsSettingsPane: View {
    let browser: BrowserStore

    @Environment(\.browserSidebarWidgetRuntime) private var sidebarWidgets
    @Bindable private var appPreferences = BrowserAppPreferenceStore.shared

    var body: some View {
        BrowserSettingsPane(.tabs) {
            BrowserNewTabSettingsSection(preferences: browser.linkPreferences)
            BrowserDurableTabSettingsSection(preferences: appPreferences)
            #if os(macOS)
                BrowserSplitFocusSettingsSection()
                BrowserRecentTabsSettingsSection()
            #endif
            BrowserTabTidyingSettingsSection(preferences: appPreferences)
            if let sidebarWidgets {
                BrowserSidebarWidgetSettingsSection(runtime: sidebarWidgets)
            }
        }
    }
}

struct BrowserNewTabSettingsSection: View {
    static let controlIdentifier =
        "focus-new-tabs-opened-from-links-toggle"

    let preferences: BrowserLinkPreferenceStore

    var body: some View {
        Section {
            Toggle(
                "Switch to tabs opened from links",
                isOn: preferences.binding(.focusesNewTabs, reading: \.focusesNewTabs)
            )
            .accessibilityIdentifier(Self.controlIdentifier)

            Toggle(
                "Follow tabs moved to another Space",
                isOn: preferences.binding(.followsMovedTabs, reading: \.followsMovedTabs)
            )
            .accessibilityIdentifier("follow-tabs-moved-to-another-space-toggle")
        } header: {
            Text("New tabs")
        } footer: {
            CrestFormFootnote("Hold Shift as you open a link to do the opposite.")
        }
    }
}

/// Whether the sidebar offers Tidy, and where its model runs. Off by default,
/// and can't be turned on where Apple Intelligence is unavailable, though it
/// can always be turned off, which deletes its word list.
struct BrowserTabTidyingSettingsSection: View {
    @Bindable var preferences: BrowserAppPreferenceStore

    var body: some View {
        Section {
            Toggle("Offer Tidy for open tabs", isOn: $preferences.offersTabTidying)
                .disabled(!OnDeviceTabTidyingService.isModelAvailable && !preferences.offersTabTidying)
                .accessibilityIdentifier("offer-tab-tidying-toggle")
        } header: {
            Text("Tidy")
        } footer: {
            CrestFormFootnote(footnote)
        }
    }

    private var footnote: LocalizedStringKey {
        guard OnDeviceTabTidyingService.isModelAvailable else { return "Requires Apple Intelligence." }
        let downloads = TidyModelDownloads.shared
        if preferences.offersTabTidying, downloads.isDownloading {
            return "Downloading Tidy's word list…"
        }
        if preferences.offersTabTidying, downloads.didFail {
            return "Couldn't download Tidy's word list. Turn Tidy off and on to try again."
        }
        return
            "Groups open tabs under headers using Apple Intelligence on this device. Turning it on downloads a 30 MB word list. Tab titles and addresses never leave this device."
    }
}

struct BrowserSidebarWidgetSettingsSection: View {
    let runtime: BrowserSidebarWidgetRuntime

    var body: some View {
        let registrations = runtime.userControllableRegistrations()
        if !registrations.isEmpty {
            Section("Sidebar widgets") {
                ForEach(registrations) { registration in
                    Toggle(
                        registration.settingsTitle,
                        isOn: enabledBinding(for: registration.id)
                    )
                    .accessibilityIdentifier(
                        "sidebar-widget-\(registration.id.rawValue)-toggle"
                    )
                }
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
