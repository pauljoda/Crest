import SwiftUI

struct BrowserExtensionDiscoverySection: View {
    @Bindable var model: BrowserExtensionDiscoveryModel
    let isPackageImportBusy: Bool
    let choosePackage: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: CrestSpacing.medium) {
                Text(
                    "Find Safari Web Extensions in installed apps and Safari-created custom extensions, install a Chrome or Firefox package, or choose an unpacked extension. Crest inspects every extension before adding it."
                )
                .font(.callout)
                .foregroundStyle(.secondary)

                HStack(spacing: CrestSpacing.small) {
                    Button(
                        "Scan Installed",
                        systemImage: "sparkle.magnifyingglass"
                    ) {
                        Task { await model.scanInstalled() }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Choose App…", systemImage: "plus.app") {
                        model.isChoosingSafariApplication = true
                    }
                    .buttonStyle(.bordered)

                    Button(
                        "Install Package…",
                        systemImage: "doc.badge.plus",
                        action: choosePackage
                    )
                    .buttonStyle(.bordered)

                    Button(
                        "Load Unpacked…",
                        systemImage: "folder.badge.plus",
                        action: model.chooseUnpackedExtension
                    )
                    .buttonStyle(.bordered)
                }
                .disabled(model.isBusy || isPackageImportBusy)
            }
            .padding(.vertical, CrestSpacing.extraSmall)

            if model.isScanningInstalled {
                HStack(spacing: CrestSpacing.small) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Scanning Installed Extensions…")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            if model.needsSafariCustomExtensionAccess,
                !model.isScanningInstalled
            {
                HStack(alignment: .center, spacing: CrestSpacing.medium) {
                    Label {
                        VStack(
                            alignment: .leading,
                            spacing: CrestSpacing.extraSmall
                        ) {
                            Text("Include Safari Custom Extensions")
                                .font(.body.weight(.medium))
                            Text(
                                "Safari keeps extensions it creates in a privacy-protected folder. Choose that folder once so Crest can inspect and copy them."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "hand.raised")
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: CrestSpacing.medium)

                    Button("Choose Safari Folder…") {
                        model.chooseSafariCustomExtensionFolder()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, CrestSpacing.extraSmall)
            }

            if model.didScanInstalled,
                model.installableItems.isEmpty,
                !model.isScanningInstalled,
                !model.needsSafariCustomExtensionAccess
            {
                Label {
                    VStack(
                        alignment: .leading,
                        spacing: CrestSpacing.extraSmall
                    ) {
                        Text("No Installable Extensions Found")
                            .font(.body.weight(.medium))
                        Text(
                            "You can still choose a signed extension app, install a Chrome or Firefox package, or load an unpacked WebExtension."
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
                        Task { await model.install(item) }
                    }
                )
            }
        } header: {
            Text("Find Extensions")
        } footer: {
            Text(
                "Safari-created extensions are copied into this Space and reviewed with fresh Crest permissions. Safari content blockers and legacy Safari App Extensions can’t be hosted by another browser."
            )
        }
    }
}
