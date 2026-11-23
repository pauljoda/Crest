import SwiftUI

/// Who the page is: its icon and title, its host with a lock tinted by the
/// connection, which opens Connection, and the Space it is in, whose chip
/// opens the page in another of the window's Spaces.
struct SiteControlsHeader: View {
    let model: SiteControlsModel

    @Environment(\.siteControlsMetrics) private var metrics

    var body: some View {
        HStack(spacing: CrestSpacing.small + 2) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: model.title)
                    .font(metrics.titleFont)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let host = model.host {
                    hostButton(host)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let space = model.platform.space {
                SiteControlsSpaceChip(model: model, space: space)
            }
        }
        .frame(minHeight: metrics.faviconSize + 4)
    }

    @ViewBuilder
    private var icon: some View {
        Group {
            if let tab = model.platform.tab {
                TabStateFaviconView(
                    tab: tab, favicons: model.core.state.favicons, profileID: model.page.profileID,
                    size: metrics.faviconSize * 0.6)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: metrics.faviconSize * 0.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: metrics.faviconSize, height: metrics.faviconSize)
        .background(CrestColor.chromeSurface, in: .rect(cornerRadius: CrestRadius.compact))
        .accessibilityHidden(true)
    }

    private func hostButton(_ host: String) -> some View {
        Button {
            model.open(.connection)
        } label: {
            HStack(spacing: CrestSpacing.extraSmall) {
                Image(systemName: model.security.isSecure ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: metrics.glyphSize * 0.65, weight: .semibold))
                    .foregroundStyle(model.security.isSecure ? Color.secondary : CrestColor.danger)
                Text(verbatim: host)
                    .lineLimit(1)
                    .truncationMode(.middle)
                CrestFormDisclosureChevron()
                    .scaleEffect(0.8)
            }
            .font(metrics.detailFont)
            .foregroundStyle(.secondary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(String(localized: model.connectionTitle)), \(host)"))
        .accessibilityHint("Shows the connection")
        .accessibilityIdentifier("site-controls-connection")
        .help(Text(model.connectionTitle))
    }
}

/// The page's Space, as a chip that opens a menu of the window's other
/// Spaces, grouped as the window groups them, to open the page in as a
/// Quick Window there for the same site under another account.
private struct SiteControlsSpaceChip: View {
    let model: SiteControlsModel
    let space: SpaceModel

    @Environment(\.siteControlsMetrics) private var metrics

    var body: some View {
        let groups = model.platform.otherSpaceGroups
        let opens = model.page.live.documentURL.map { ExternalWebLink.accepts($0) } == true && !groups.isEmpty
        Menu {
            Section("Open This Page in") {
                ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                    if index > 0 { Divider() }
                    ForEach(group) { other in
                        Button {
                            model.platform.dismiss()
                            model.platform.openPage(in: other)
                        } label: {
                            BrowserSpaceIdentityLabel(space: other)
                        }
                    }
                }
            }
            .crestMenuActionLabelStyle()
        } label: {
            HStack(spacing: 5) {
                BrowserSpaceIdentityLabel(space: space, iconSize: metrics.chipHeight * 0.62)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                if opens {
                    Image(systemName: "chevron.down")
                        .font(.system(size: metrics.chipHeight * 0.36, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .font(metrics.detailFont.weight(.semibold))
            .padding(.leading, 5)
            .padding(.trailing, 7)
            .frame(height: metrics.chipHeight)
            .contentShape(.capsule)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(
            CrestChromeButtonStyle(controlSize: nil, cornerRadius: metrics.chipHeight / 2, showsRestingFill: true)
        )
        .disabled(!opens)
        .fixedSize()
        .accessibilityLabel(Text("\(space.identity.name) Space"))
        .accessibilityHint(opens ? Text("Opens this page in another Space") : Text(verbatim: ""))
        .accessibilityIdentifier("site-control-open-in-space")
        .help(opens ? Text("Open This Page in Another Space") : Text(verbatim: space.identity.name))
    }
}
