import SwiftUI
import UniformTypeIdentifiers

/// The downloads started in a Quick Window, which has no sidebar for them to
/// fly to, as cards rising into its bottom-leading corner. Each shows its
/// file's progress and, once finished, shows the file in Finder when pressed,
/// until it leaves a moment after its download ends.
struct BrowserMacDownloadTrayLayer: View {
    /// The downloads of the window's browsing mode, whose feedback events say
    /// which downloads started here and whose records say how far they are.
    let downloadCenter: BrowserDownloadCenter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The downloads this window shows, which live as long as the window does.
    @State private var tray = BrowserMacDownloadTrayState()
    /// The window the layer is in, known once it joins one.
    @State private var windowIdentifier: ObjectIdentifier?

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.small) {
            ForEach(shownDownloads) { download in
                BrowserMacDownloadTrayCard(download: download) {
                    tray.dismiss(download.id)
                }
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .bottom)
                            .combined(with: .scale(scale: 0.6, anchor: .bottomLeading))
                            .combined(with: .opacity)
                )
            }
        }
        .padding(CrestSpacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .animation(
            reduceMotion ? CrestMotion.reducedMotionFade : CrestMotion.downloadCardEntrance,
            value: tray.downloadIDs
        )
        .background(alignment: .topLeading) {
            BrowserDownloadFeedbackWindowIdentityReader(identifier: $windowIdentifier)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onChange(of: downloadCenter.feedbackEvents, initial: true) { _, events in
            adopt(events, in: windowIdentifier)
        }
        .onChange(of: windowIdentifier) { _, window in
            adopt(downloadCenter.feedbackEvents, in: window)
        }
    }

    /// The records of the downloads the tray shows, oldest first. One whose
    /// record is gone is no longer drawn.
    private var shownDownloads: [DownloadState] {
        tray.downloadIDs.compactMap(downloadCenter.item)
    }

    /// Shows the downloads among `events` that started in `window`, and tells
    /// VoiceOver a download started.
    private func adopt(_ events: [BrowserDownloadFeedbackEvent], in window: ObjectIdentifier?) {
        if tray.adopt(events, in: window) {
            AccessibilityNotification.Announcement(String(localized: "Download started")).post()
        }
    }
}

/// One download as a dark card: its file, its name and one line of detail. A
/// finished card shows the file in Finder when pressed and can be dragged out
/// as the file.
private struct BrowserMacDownloadTrayCard: View {
    /// The narrowest card, which a short name still fills out.
    private static let minimumWidth: CGFloat = 220
    /// The widest card; a longer name is shortened in the middle.
    private static let maximumWidth: CGFloat = 300
    /// The side of the square that holds the file glyph and its ring.
    private static let iconSize: CGFloat = 28
    /// The width of the progress ring around the file glyph.
    private static let progressLineWidth: CGFloat = 2

    /// The download's record, as the core last published it.
    let download: DownloadState
    /// Takes the card out of the tray.
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// Whether the pointer rests on the card, which keeps it in place.
    @State private var isHovering = false

    var body: some View {
        content
            .frame(minWidth: Self.minimumWidth, maxWidth: Self.maximumWidth, alignment: .leading)
            .fixedSize()
            .background(.black, in: .rect(cornerRadius: CrestRadius.compact))
            .overlay {
                RoundedRectangle(cornerRadius: CrestRadius.compact)
                    .strokeBorder(CrestColor.subtleBorder)
            }
            // The card is dark on every page, the way a download toast reads.
            .environment(\.colorScheme, .dark)
            .shadow(
                color: .black.opacity(reduceTransparency ? 0 : CrestOpacity.controlShadow),
                radius: BrowserRootMetrics.noticeShadowRadius,
                y: BrowserRootMetrics.noticeShadowYOffset
            )
            .onHover { isHovering = $0 }
            .task(id: lingers) {
                guard lingers else { return }
                try? await Task.sleep(for: BrowserMacDownloadTrayState.settledLifetime)
                guard !Task.isCancelled else { return }
                dismiss()
            }
    }

    /// The card's face, which is a button once there is a finished file to go
    /// to.
    @ViewBuilder
    private var content: some View {
        if let destination, let fileURL = download.destinationURL {
            Button {
                destination.send(fileURL, to: BrowserWorkspaceFileOpener())
                dismiss()
            } label: {
                label
            }
            .buttonStyle(.plain)
            .crestHoverSurface(cornerRadius: CrestRadius.compact)
            .browserDownloadFileDrag(download)
            .help(Text(destination.title))
            .accessibilityLabel(Text(destination.title))
            .accessibilityValue(Text(verbatim: download.filename))
        } else {
            label
                .accessibilityElement(children: .combine)
        }
    }

    /// The file glyph beside the name and its detail.
    private var label: some View {
        HStack(spacing: CrestSpacing.medium) {
            icon
                .frame(width: Self.iconSize, height: Self.iconSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: CrestSpacing.extraExtraSmall) {
                Text(download.filename)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                detail
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, CrestSpacing.medium)
        .padding(.vertical, CrestSpacing.small + CrestSpacing.extraSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    /// The file, ringed by its progress while the download is live. The ring
    /// turns while the size is unknown.
    private var icon: some View {
        ZStack {
            Image(systemName: "doc.fill")
                .font(.system(size: download.phase.isLive ? 12 : 22, weight: .regular))
                .foregroundStyle(.primary)
            if download.phase.isLive {
                BrowserDownloadProgressRing(
                    fraction: download.knownProgress,
                    tint: .primary,
                    lineWidth: Self.progressLineWidth
                )
            }
        }
    }

    /// How far the download has come, and once it has finished, what kind of
    /// file it left, as Finder names it.
    private var detail: Text {
        let presentation = BrowserDownloadRowPresentation.resolve(item: download)
        if download.phase.isComplete, let kind = fileKind {
            return Text(verbatim: kind).foregroundStyle(.secondary)
        }
        if presentation.statusNeedsAttention {
            return presentation.statusText.view.foregroundStyle(.red)
        }
        guard download.phase.isTransferring, presentation.showsTransferMetrics else {
            return presentation.statusText.view.foregroundStyle(.secondary)
        }
        guard let totalBytes = presentation.totalBytes else {
            return Text("\(presentation.bytesReceived, format: .byteCount(style: .file)) downloaded")
                .foregroundStyle(.secondary)
        }
        return Text(
            "\(presentation.bytesReceived, format: .byteCount(style: .file)) of \(totalBytes, format: .byteCount(style: .file)) · \(presentation.progress, format: .percent.precision(.fractionLength(0)))"
        )
        .foregroundStyle(.secondary)
    }

    /// The file's kind as Finder names it, such as "Zip archive", when its
    /// extension names one.
    private var fileKind: String? {
        UTType(filenameExtension: (download.filename as NSString).pathExtension)?.localizedDescription
    }

    /// Where pressing the card takes a finished file.
    private var destination: BrowserUtilityDownloadDestination? {
        BrowserUtilityDownloadDestination.primary(for: download.phase, among: [.open, .revealInFinder])
    }

    /// A card stays while its download runs and while the pointer rests on it.
    private var lingers: Bool {
        !download.phase.isLive && !isHovering
    }
}
