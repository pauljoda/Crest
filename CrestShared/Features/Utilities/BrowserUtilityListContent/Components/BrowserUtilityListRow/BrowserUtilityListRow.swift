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
                        subtitle: archiveSubtitle(archived)
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
                BrowserUtilityListRowLabel(
                    title: download.filename,
                    subtitle: download.state.utilityStatusText.view,
                    subtitleIsFailure: download.state.needsAttention
                ) {
                    BrowserDownloadStatusIcon(item: download)
                } trailing: {
                    BrowserDownloadRowAction(
                        item: download,
                        destinations: actions.downloadDestinations,
                        perform: {
                            actions.performDownloadAction($0, assignment)
                        }
                    )
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(
                    BrowserUtilityAccessibilityID.downloadRow(download.id)
                )
            }
        }
        .crestHoverSurface(
            cornerRadius: CrestLayout.sidebarControlCornerRadius
        )
    }

    private func archiveSubtitle(_ archived: ArchivedTab) -> Text {
        guard let host = archived.tab.url?.host() else {
            return Text(archived.reason.utilityTitle)
        }
        return Text(host)
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
