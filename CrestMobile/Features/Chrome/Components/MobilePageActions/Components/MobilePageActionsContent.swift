import SwiftUI

struct MobilePageActionsContent: View {
    let browser: BrowserStore
    let pages: any MobilePageActions
    var downloadsAccess: MobileDownloadsMenuAccess? = nil
    var hideToolbar: (() -> Void)? = nil

    var body: some View {
        if let downloadsAccess {
            Button(action: downloadsAccess.open) {
                Label(downloadsAccess.rowTitle, systemImage: "arrow.down.circle")
            }
            .accessibilityLabel("Downloads")
            .accessibilityValue(
                BrowserChromeAccessibility.countValue(
                    downloadsAccess.newItemCount,
                    singular: "new download",
                    plural: "new downloads"
                )
            )
            .accessibilityIdentifier("page-actions-downloads")
        }

        if let notice = pages.blockedPopupNotice {
            Section("Automatic Pop-ups") {
                switch notice.status {
                case .blocked:
                    Button {
                        pages.allowAutomaticPopupsForBlockedSite()
                    } label: {
                        Label(
                            "Allow Automatic Pop-ups",
                            systemImage: "macwindow.badge.plus"
                        )
                    }
                    .accessibilityLabel(
                        notice.allowActionAccessibilityLabel
                    )
                    .accessibilityHint(
                        notice.allowActionAccessibilityHint
                    )
                    .accessibilityIdentifier("allow-blocked-automatic-popups")
                case .allowedAwaitingRetry:
                    Label(notice.title, systemImage: "checkmark.circle")
                        .accessibilityLabel(
                            Text(verbatim: "\(notice.title). \(notice.guidance)")
                        )
                    Text(notice.guidance)
                        .foregroundStyle(.secondary)
                }
            }
        }

        ControlGroup {
            if let url = pages.activeURL {
                ShareLink(item: url) {
                    Label("Share…", systemImage: "square.and.arrow.up")
                }
            }

            Button("Copy Page Link", systemImage: "link") {
                pages.copyPageLink()
            }

            Button(
                pages.activePage?.isLoading == true ? "Stop" : "Reload",
                systemImage: pages.activePage?.isLoading == true ? "xmark" : "arrow.clockwise"
            ) {
                pages.reloadOrStop()
            }

        }
        .labelStyle(.iconOnly)

        Button(
            pages.preferredContentModeActionTitle,
            systemImage: pages.activePage?.isRequestingDesktopSite == true
                ? "iphone"
                : "desktopcomputer"
        ) {
            pages.togglePreferredContentMode()
        }

        Button(
            pages.readerModeActionTitle,
            systemImage: pages.readerModeState.isActive ? "doc.plaintext.fill" : "doc.plaintext"
        ) {
            pages.toggleReaderMode()
        }
        .disabled(!pages.readerModeState.canToggle)

        Button(
            contentBlockingActionTitle,
            systemImage: pages.activePage?.isContentBlockingActive == true
                ? "shield.lefthalf.filled"
                : "shield.slash"
        ) {
            Task { await contentBlockingAction.perform() }
        }

        Button("Find in Page", systemImage: "text.magnifyingglass") {
            pages.presentFind()
        }

        if let hideToolbar {
            Button("Hide Toolbar", systemImage: "chevron.down") {
                hideToolbar()
            }
        }

        Section("Page Zoom") {
            Button("Zoom Out", systemImage: "minus.magnifyingglass") {
                pages.zoomOut()
            }

            Button("Actual Size (\(pages.pageZoomLabel))", systemImage: "1.magnifyingglass") {
                pages.resetZoom()
            }

            Button("Zoom In", systemImage: "plus.magnifyingglass") {
                pages.zoomIn()
            }
        }

        Section {
            Button("Copy as Markdown", systemImage: "text.badge.checkmark") {
                pages.copyPageLinkAsMarkdown()
            }

            Menu("Share & Export…", systemImage: "square.and.arrow.up") {
                Group {
                    if let url = pages.activeURL {
                        ShareLink(item: url) {
                            Label("Share…", systemImage: "square.and.arrow.up")
                        }
                    }

                    Button("Print…", systemImage: "printer") {
                        pages.printPage()
                    }

                    Menu("Export as PDF…", systemImage: "doc.richtext") {
                        ForEach(MobileBrowserFileExportDestination.allCases) {
                            destination in
                            Button(
                                destination.title,
                                systemImage: destination.systemImage
                            ) {
                                pages.exportPDF(to: destination)
                            }
                        }
                        .crestMenuActionLabelStyle()
                    }

                    Menu("Export Web Archive…", systemImage: "archivebox") {
                        ForEach(MobileBrowserFileExportDestination.allCases) {
                            destination in
                            Button(
                                destination.title,
                                systemImage: destination.systemImage
                            ) {
                                pages.exportWebArchive(to: destination)
                            }
                        }
                        .crestMenuActionLabelStyle()
                    }
                }
                .crestMenuActionLabelStyle()
            }
        }
    }

    private var contentBlockingAction: MobileContentBlockingAction {
        MobileContentBlockingAction(browser: browser, pages: pages)
    }

    private var contentBlockingActionTitle: LocalizedStringResource {
        MobileContentBlockingActionTitle.resolve(
            policy: browser.selectedSpace?.browsingPreferences
                .contentBlockingPolicy
        )
    }
}
