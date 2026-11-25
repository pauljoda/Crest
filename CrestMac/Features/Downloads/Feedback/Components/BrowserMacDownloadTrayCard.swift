import SwiftUI

/// One download as a card on Crest's floating surface: its file ringed by its
/// progress, its name and one line of how far it is. Once finished it says
/// "Downloaded" with the window notice's check, shows the file in Finder when
/// pressed and can be dragged out as the file.
struct BrowserMacDownloadTrayCard: View {
    // MARK: - Static Variables

    /// The narrowest card, which a short name still fills out.
    private static let minimumWidth: CGFloat = 220
    /// The widest card; a longer name is shortened in the middle.
    private static let maximumWidth: CGFloat = 300
    /// The side of the square that holds the file's symbol and its ring.
    private static let iconSize: CGFloat = 28
    /// The width of the progress ring around the file's symbol.
    private static let progressLineWidth: CGFloat = 2

    // MARK: - Variables

    /// The download's record, as the core last published it.
    let download: DownloadState
    /// Takes the card out of the tray.
    let dismiss: () -> Void

    /// Whether the pointer rests on the card, which keeps it in place.
    @State private var isHovering = false
    /// Whether an assistive technology such as VoiceOver is on the card,
    /// which keeps it in place as the pointer does.
    @AccessibilityFocusState private var isAccessibilityFocused: Bool

    // MARK: - Actions - Drawing

    var body: some View {
        content
            .accessibilityFocused($isAccessibilityFocused)
            .padding(CrestSpacing.small)
            .frame(minWidth: Self.minimumWidth, maxWidth: Self.maximumWidth, alignment: .leading)
            .fixedSize()
            .crestFloatingFlyoutStyle(in: .rect(cornerRadius: CrestRadius.card))
            .crestElevation(.panel)
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
            .buttonStyle(.crestFormRow)
            .browserDownloadFileDrag(download)
            .help(Text(destination.title))
            .accessibilityLabel(Text(destination.title))
            .accessibilityValue(Text(verbatim: download.filename))
        } else {
            label
                .accessibilityElement(children: .combine)
        }
    }

    /// The file's symbol beside its name and how far it is.
    private var label: some View {
        HStack(spacing: CrestSpacing.medium) {
            icon
                .frame(width: Self.iconSize, height: Self.iconSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: CrestSpacing.extraExtraSmall) {
                Text(download.filename)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                detail
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    /// The file's kind, ringed by its progress while it downloads, and the
    /// notice's check once it has.
    @ViewBuilder
    private var icon: some View {
        if download.phase.isComplete {
            Image(systemName: BrowserNotice.downloadFinishedSymbol)
                .font(.title2)
                .foregroundStyle(.tint)
        } else {
            ZStack {
                Image(systemName: BrowserDownloadFileKind(filename: download.filename).symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if download.phase.isLive {
                    BrowserDownloadProgressRing(
                        fraction: [download].notificationProgress, tint: .accentColor,
                        lineWidth: Self.progressLineWidth)
                }
            }
        }
    }

    /// How far the download has come, or that it finished, in the words the
    /// downloads list and the window's notice use.
    private var detail: Text {
        if download.phase.isComplete { return Text("Downloaded").foregroundStyle(.secondary) }
        let presentation = BrowserDownloadRowPresentation.resolve(item: download)
        if presentation.statusNeedsAttention {
            return presentation.statusText.view.foregroundStyle(CrestColor.danger)
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

    /// Where pressing the card takes a finished file.
    private var destination: BrowserUtilityDownloadDestination? {
        BrowserUtilityDownloadDestination.primary(for: download.phase, among: [.open, .revealInFinder])
    }

    /// A card stays while its download runs, while the pointer rests on it
    /// and while VoiceOver is on it.
    private var lingers: Bool {
        !download.phase.isLive && !isHovering && !isAccessibilityFocused
    }
}
