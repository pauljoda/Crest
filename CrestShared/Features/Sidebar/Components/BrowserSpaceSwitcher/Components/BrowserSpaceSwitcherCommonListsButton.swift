import SwiftUI

/// The switcher's page-side accessory: one control for the archive, history,
/// and downloads lists, badged when downloads have finished unseen and ringed
/// by their progress while downloads run. It wears the symbol of the list it
/// opens, which its menu changes.
struct BrowserSpaceSwitcherCommonListsButton: View {
    // MARK: - Static Variables

    /// The width of the ring that shows the running downloads' progress
    /// around the button.
    private static let progressLineWidth: CGFloat = 2.5

    // MARK: - Variables

    let isExpanded: Bool
    let surface: BrowserUtilitySurface
    let downloads: [DownloadState]
    let newDownloads: [DownloadState]
    let badgeColor: Color
    let action: () -> Void
    let choose: (BrowserUtilitySurface) -> Void
    let recordFrame: (CGRect) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(macOS)
        @Environment(BrowserMacDownloadFeedbackState.self) private var downloadFeedback:
            BrowserMacDownloadFeedbackState?
    #endif

    var body: some View {
        Button("Common Lists", systemImage: openedSurface.systemImage, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(
                width: BrowserSpaceSwitcherLayout.utilityButtonSize,
                height: BrowserSpaceSwitcherLayout.utilityButtonSize
            )
            .symbolVariant(isExpanded ? .fill : .none)
            .background {
                if isDownloading {
                    BrowserDownloadProgressRing(
                        fraction: downloads.notificationProgress, tint: badgeColor,
                        lineWidth: Self.progressLineWidth
                    )
                    .transition(.opacity)
                }
            }
            .animation(CrestMotion.contentState.unlessReducingMotion(reduceMotion), value: isDownloading)
            .contextMenu {
                Picker(selection: Binding(get: { surface }, set: choose)) {
                    ForEach(BrowserUtilitySurface.all) { surface in
                        Label {
                            Text(surface.title)
                        } icon: {
                            Image(systemName: surface.systemImage)
                        }
                        .tag(surface)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.inline)
                .crestMenuActionLabelStyle()
            }
            .symbolEffect(
                .bounce,
                value: reduceMotion ? nil : arrivalTrigger
            )
            .overlay(alignment: .topTrailing) {
                if !newDownloads.isEmpty {
                    BrowserUtilityNotificationBadge(
                        count: newDownloads.count,
                        tint: downloads.badgeTint(otherwise: badgeColor),
                        // The ring around the button carries the progress.
                        progress: nil
                    )
                    .offset(
                        x: BrowserUtilitySwitcherLayout.notificationBadgeOffset,
                        y: -BrowserUtilitySwitcherLayout.notificationBadgeOffset
                    )
                }
            }
            .zIndex(newDownloads.isEmpty ? 0 : 1)
            .help("Archive, History, and Downloads")
            .accessibilityLabel(Text(openedSurface.title))
            .accessibilityValue(accessibilityValue)
            .accessibilityIdentifier("common-lists-button")
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                recordFrame(frame)
            }
    }

    /// Whether a download is moving bytes, which rings the button.
    private var isDownloading: Bool {
        downloads.contains { $0.phase.isTransferring }
    }

    /// The list a press opens now: unseen finished downloads take it to
    /// Downloads, whatever list was chosen, and the symbol says so.
    private var openedSurface: BrowserUtilitySurface {
        newDownloads.isEmpty ? surface : .downloads
    }

    private var accessibilityValue: String {
        let state = isExpanded ? "Expanded" : "Collapsed"
        guard !newDownloads.isEmpty else { return state }
        return "\(state), \(newDownloads.count) new downloads"
    }

    private enum ArrivalTrigger: Equatable {
        case flight(Int)
        case download(UUID?)
    }

    private var arrivalTrigger: ArrivalTrigger {
        #if os(macOS)
            if let downloadFeedback { return .flight(downloadFeedback.arrivalCount) }
        #endif
        return .download(newDownloads.first?.id)
    }
}

#if DEBUG
    #Preview("Download badge and expansion") {
        @Previewable @State var expanded = false
        @Previewable @State var surface = BrowserUtilitySurface.archive
        BrowserSpaceSwitcherCommonListsButton(
            isExpanded: expanded, surface: surface, downloads: [BrowserUtilityListPreviewFixture.activeDownload],
            newDownloads: [BrowserUtilityListPreviewFixture.finishedDownload], badgeColor: .indigo,
            action: { expanded.toggle() }, choose: { surface = $0 }, recordFrame: { _ in }
        ).padding()
    }
#endif
