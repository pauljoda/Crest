import SwiftUI

struct BrowserExtensionUpdatesSection: View {
    @Bindable var model: BrowserExtensionUpdateModel

    var body: some View {
        Section {
            Toggle(
                "Update Extensions Automatically",
                isOn: automaticUpdateBinding
            )

            Picker("Update Frequency", selection: updateFrequencyBinding) {
                ForEach(BrowserExtensionUpdateFrequency.allCases) { frequency in
                    Text(frequency.title).tag(frequency)
                }
            }
            .disabled(!model.preferences.isAutomaticUpdateEnabled)

            Button(action: checkForUpdates) {
                Label("Check for Updates Now", systemImage: "arrow.clockwise")
            }
            .disabled(model.isChecking || !model.hasUpdatableExtensions)

            BrowserExtensionUpdateStatus(model: model)
        } header: {
            Text("Updates")
        } footer: {
            Text(
                "Crest records where each extension came from and updates only the ones installed from the Chrome Web Store, using the same signature and identity checks as the original install. Extensions you switched off, unpacked extensions, and extensions loaded from an installed app are left alone."
            )
        }
    }

    private var automaticUpdateBinding: Binding<Bool> {
        Binding {
            model.preferences.isAutomaticUpdateEnabled
        } set: { isEnabled in
            model.setAutomaticUpdateEnabled(isEnabled)
        }
    }

    private var updateFrequencyBinding: Binding<BrowserExtensionUpdateFrequency> {
        Binding {
            model.preferences.updateFrequency
        } set: { frequency in
            model.setUpdateFrequency(frequency)
        }
    }

    private func checkForUpdates() {
        Task { await model.checkForUpdatesNow() }
    }
}
