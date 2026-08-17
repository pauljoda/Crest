import SwiftUI

struct BrowserExtensionDiscoverySection: View {
    @Bindable var model: BrowserExtensionDiscoveryModel

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: CrestSpacing.medium) {
                Text(
                    "Find signed Safari Web Extensions in installed apps, or choose another source. Crest verifies each extension before offering it."
                )
                .font(.callout)
                .foregroundStyle(.secondary)

                HStack(spacing: CrestSpacing.small) {
                    Button(
                        "Scan for Apps",
                        systemImage: "sparkle.magnifyingglass"
                    ) {
                        Task { await model.scanApplications() }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Choose App…", systemImage: "plus.app") {
                        model.isChoosingSafariApplication = true
                    }
                    .buttonStyle(.bordered)

                    Button(
                        "Load Unpacked…",
                        systemImage: "folder.badge.plus",
                        action: model.chooseUnpackedExtension
                    )
                    .buttonStyle(.bordered)
                }
                .disabled(model.isBusy)
            }
            .padding(.vertical, CrestSpacing.extraSmall)

            if model.isScanningApplications {
                HStack(spacing: CrestSpacing.small) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Scanning Applications…")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            if model.didScanApplications,
                model.installableItems.isEmpty,
                !model.isScanningApplications
            {
                Label {
                    VStack(
                        alignment: .leading,
                        spacing: CrestSpacing.extraSmall
                    ) {
                        Text("No Installable Extensions Found")
                            .font(.body.weight(.medium))
                        Text(
                            "You can still choose a signed extension app or load an unpacked WebExtension."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "checkmark.magnifyingglass")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, CrestSpacing.extraSmall)
            }

            if let status = model.statusMessage {
                Label(status, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            ForEach(model.installableItems) { item in
                BrowserExtensionDiscoveryRow(
                    item: item,
                    space: model.extensionsModel.space,
                    isInstalling: model.installingExtensionID == item.id,
                    isDisabled: model.installingExtensionID != nil,
                    install: {
                        Task { await model.install(item.candidate) }
                    }
                )
            }
        } header: {
            Text("Find Extensions")
        } footer: {
            Text(
                "Crest supports standards-based Safari Web Extensions. Safari content blockers and legacy Safari App Extensions can’t be hosted by another browser."
            )
        }
    }
}
