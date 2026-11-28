import SwiftUI

/// How new, pinned and saved tabs behave, Split View focus, switching between
/// recent tabs, Tidy, and the sidebar's optional widgets.
struct BrowserTabsSettingsPane: View {
    let browser: BrowserStore

    @Environment(\.browserSidebarWidgetRuntime) private var sidebarWidgets
    @Bindable private var appPreferences = BrowserAppPreferenceStore.shared

    var body: some View {
        BrowserSettingsPane(.tabs) {
            BrowserSettingsSectionSlot(.newTabs) {
                BrowserNewTabSettingsSection(preferences: browser.linkPreferences, appPreferences: appPreferences)
            }
            BrowserSettingsSectionSlot(.durableTabs) {
                BrowserDurableTabSettingsSection(preferences: appPreferences)
            }
            #if os(macOS)
                BrowserSettingsSectionSlot(.splitFocus) { BrowserSplitFocusSettingsSection() }
                BrowserSettingsSectionSlot(.recentTabs) { BrowserRecentTabsSettingsSection() }
            #endif
            BrowserSettingsSectionSlot(.tidy) { BrowserTidySettingsSection() }
            if let sidebarWidgets {
                BrowserSettingsSectionSlot(.sidebarWidgets) {
                    BrowserSidebarWidgetSettingsSection(runtime: sidebarWidgets)
                }
            }
        }
    }
}

struct BrowserNewTabSettingsSection: View {
    static let controlIdentifier =
        "focus-new-tabs-opened-from-links-toggle"

    let preferences: BrowserLinkPreferenceStore
    @Bindable var appPreferences: BrowserAppPreferenceStore

    var body: some View {
        Section {
            Toggle(isOn: preferences.binding(.focusesNewTabs, reading: \.focusesNewTabs)) {
                Text("Switch to tabs opened from links")
                Text("Hold Shift as you open a link to do the opposite.")
            }
            .accessibilityIdentifier(Self.controlIdentifier)

            Toggle(
                "Follow tabs moved to another Space",
                isOn: preferences.binding(.followsMovedTabs, reading: \.followsMovedTabs)
            )
            .accessibilityIdentifier("follow-tabs-moved-to-another-space-toggle")

            Picker("Open new tabs at", selection: $appPreferences.newTabPosition) {
                ForEach(NewTabPosition.all, id: \.self) { position in
                    Text(position.title).tag(position)
                }
            }
            .accessibilityIdentifier("new-tab-position")

            Toggle("Open new tabs in the current folder", isOn: $appPreferences.newTabsJoinFolder)
                .accessibilityIdentifier("new-tabs-join-folder-toggle")
        } header: {
            Text("New tabs")
        }
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
