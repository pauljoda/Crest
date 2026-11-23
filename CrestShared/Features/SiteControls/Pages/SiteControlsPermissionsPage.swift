import SwiftUI

/// What the site may use in the page's Space: first what it asked for, then
/// what it has not asked for yet, each with its decision, which a menu
/// changes.
struct SiteControlsPermissionsPage: View {
    let model: SiteControlsModel

    var body: some View {
        let permissions = model.permissions
        let asked = permissions.filter { model.wasAsked(for: $0.permission, decision: $0.decision) }
        let others = permissions.filter { !model.wasAsked(for: $0.permission, decision: $0.decision) }
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            if !asked.isEmpty {
                SiteControlsPageSection(title: "Asked by this site") {
                    ForEach(asked, id: \.permission) { row($0.permission, $0.decision) }
                }
            }
            SiteControlsPageSection(
                title: asked.isEmpty ? nil : "Not asked yet",
                footer: model.platform.space.map {
                    Text("Saved in \($0.identity.name). Other Spaces decide for themselves.")
                }
            ) {
                ForEach(others, id: \.permission) { row($0.permission, $0.decision) }
            }
        }
    }

    private func row(_ permission: SitePermission, _ decision: SitePermissionDecision) -> some View {
        SiteControlsRowLabel(title: Text(permission.title), symbol: permission.symbol) {
            Menu {
                Group {
                    Button(String(localized: permission.askChoiceTitle), systemImage: "questionmark.circle") {
                        model.setDecision(.ask, for: permission)
                    }
                    // The system asks each time for some capabilities, so
                    // nothing allows a site ahead of that question.
                    if !permission.isAskedBySystem {
                        Button("Allow", systemImage: "checkmark.circle") {
                            model.setDecision(.grantPersistently, for: permission)
                        }
                    }
                    Button("Block", systemImage: "nosign") {
                        model.setDecision(.denyPersistently, for: permission)
                    }
                }
                .crestMenuActionLabelStyle()
            } label: {
                HStack(spacing: 4) {
                    Text(permission.title(for: decision))
                    Image(systemName: "chevron.up.chevron.down")
                        .imageScale(.small)
                }
                .foregroundStyle(.secondary)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel(Text(permission.title))
            .accessibilityValue(Text(permission.title(for: decision)))
            .accessibilityIdentifier("site-permission-\(permission.name)")
        }
    }
}
