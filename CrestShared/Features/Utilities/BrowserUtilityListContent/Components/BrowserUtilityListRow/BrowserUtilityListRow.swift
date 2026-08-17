import SwiftUI

struct BrowserUtilityListRow: View {
    let item: BrowserUtilityListItem
    let assignment: BrowserSpaceRuntimeAssignment
    let actions: BrowserUtilityListActions

    var body: some View {
        Group {
            switch item {
            case .archive(let archived):
                Button {
                    actions.restoreArchivedTab(archived.id, assignment)
                } label: {
                    BrowserUtilityListRowLabel(
                        title: archived.tab.displayTitle,
                        subtitle: archiveSubtitle(archived),
                        subtitleStyle: AnyShapeStyle(
                            archived.reason.utilityTint
                        )
                    ) {
                        TabFaviconView(
                            tab: archived.tab,
                            profileID: assignment.profileID
                        )
                    } trailing: {
                        Image(systemName: "arrow.uturn.backward")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Restore \(archived.tab.displayTitle)")
                .accessibilityIdentifier(
                    BrowserTabAccessibilityID.archivedRow(archived.id)
                )

            case .history(let entry):
                Button {
                    actions.openHistoryEntry(entry, assignment)
                } label: {
                    BrowserUtilityListRowLabel(
                        title: entry.title,
                        subtitle: historySubtitle(entry)
                    ) {
                        Image(systemName: "globe")
                    } trailing: {
                        Image(systemName: "arrow.up.forward")
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(entry.title)")
                .accessibilityIdentifier(
                    BrowserUtilityAccessibilityID.historyRow(entry.id)
                )

            case .download(let download):
                BrowserUtilityDownloadRow(
                    download: download,
                    assignment: assignment,
                    actions: actions
                )
            }
        }
        .crestHoverSurface(
            cornerRadius: CrestLayout.sidebarControlCornerRadius
        )
    }

    private func archiveSubtitle(_ archived: ArchivedTab) -> Text {
        let icon = Image(systemName: archived.reason.utilitySystemImage)
        let status = Text(archived.reason.utilityTitle)
        if let host = archived.tab.url?.host() {
            return Text("\(icon) \(status) · \(host)")
        }
        return Text("\(icon) \(status)")
    }

    private func historySubtitle(_ entry: BrowserHistoryEntry) -> Text {
        let host = entry.url.host() ?? entry.url.absoluteString
        guard entry.visitCount > 1 else { return Text(host) }
        return Text(
            BrowserUtilityPresentation.historyVisits(
                host: host,
                count: entry.visitCount
            )
        )
    }

}

private struct BrowserUtilityDownloadRow: View {
    let download: BrowserDownloadItem
    let assignment: BrowserSpaceRuntimeAssignment
    let actions: BrowserUtilityListActions

    var body: some View {
        HStack(spacing: 0) {
            if let primaryDestination {
                Button {
                    perform(.open(download.id, primaryDestination))
                } label: {
                    label
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text(primaryDestination.title))
                .accessibilityValue(download.filename)
            } else {
                label
            }

            BrowserDownloadRowAction(
                item: download,
                destinations: actions.downloadDestinations,
                perform: perform
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            BrowserUtilityAccessibilityID.downloadRow(download.id)
        )
    }

    private var label: some View {
        BrowserUtilityListRowLabel(
            title: download.filename,
            subtitle: download.state.utilityStatusText.view,
            subtitleIsFailure: download.state.needsAttention
        ) {
            BrowserDownloadStatusIcon(item: download)
        }
    }

    private var primaryDestination: BrowserUtilityDownloadDestination? {
        BrowserUtilityDownloadPrimaryActionPolicy.destination(
            for: download.state,
            availableDestinations: actions.downloadDestinations
        )
    }

    private func perform(_ action: BrowserUtilityDownloadAction) {
        actions.performDownloadAction(action, assignment)
    }
}
