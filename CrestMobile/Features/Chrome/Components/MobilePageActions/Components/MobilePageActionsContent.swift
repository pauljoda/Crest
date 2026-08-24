import SwiftUI

struct MobilePageActionsContent: View {
    let browser: BrowserStore
    let pages: any MobilePageActions
    var hideToolbar: (() -> Void)? = nil

    var body: some View {
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
