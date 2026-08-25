import SwiftUI

struct BrowserDownloadStatusIcon: View {
    let item: BrowserDownloadItem

    var body: some View {
        switch item.state {
        case .preparing:
            ProgressView().controlSize(.small)
        case .awaitingApproval:
            Image(systemName: "exclamationmark.shield.fill").foregroundStyle(.orange)
        case .downloading:
            ZStack {
                Image(
                    systemName: BrowserDownloadFileIconPolicy.systemImage(
                        for: item.filename
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                Circle().stroke(.secondary.opacity(0.25), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: max(item.progress, 0.02))
                    .stroke(.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .padding(2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Download Progress")
            .accessibilityValue(
                Text(
                    BrowserDownloadProgressPolicy.normalized(item.progress),
                    format: .percent.precision(.fractionLength(0))
                )
            )
        case .finished:
            Image(
                systemName: BrowserDownloadFileIconPolicy.systemImage(
                    for: item.filename
                )
            )
        case .blockedAutomaticDownload:
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(.orange)
        case .canceled:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }
}

enum BrowserDownloadFileIconPolicy {
    static func systemImage(for filename: String) -> String {
        switch (filename as NSString).pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "svg":
            "photo.fill"
        case "pdf":
            "doc.richtext.fill"
        case "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar":
            "archivebox.fill"
        case "mp3", "m4a", "aac", "wav", "aiff", "flac", "ogg":
            "waveform"
        case "mov", "mp4", "m4v", "avi", "mkv", "webm":
            "film.fill"
        case "txt", "md", "rtf", "doc", "docx", "pages", "csv":
            "doc.text.fill"
        case "dmg", "iso", "pkg":
            "externaldrive.fill"
        default:
            "doc.fill"
        }
    }
}

/// Decorative, bounded feedback for a trusted link activation becoming a
/// download. The durable affordance remains the Downloads badge and row; this
/// layer never receives hit testing or accessibility focus.
struct BrowserDownloadFeedbackLayer: View {
    let events: [BrowserDownloadFeedbackEvent]
    let profileID: UUID?
    let spaceID: SpaceID?
    let destinationFrameInGlobal: CGRect?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var windowIdentifier: ObjectIdentifier?

    var body: some View {
        GeometryReader { proxy in
            if let destinationFrameInGlobal {
                let rootFrame = proxy.frame(in: .global)
                let destination = CGPoint(
                    x: destinationFrameInGlobal.midX - rootFrame.minX,
                    y: destinationFrameInGlobal.midY - rootFrame.minY
                )
                ForEach(Array(visibleEvents.enumerated()), id: \.element.id) {
                    index,
                    event in
                    if rootFrame.insetBy(dx: -36, dy: -36).contains(
                        event.source.pointInGlobal
                    ) {
                        BrowserDownloadFeedbackIcon(
                            filename: event.filename,
                            source: CGPoint(
                                x: event.source.pointInGlobal.x - rootFrame.minX,
                                y: event.source.pointInGlobal.y - rootFrame.minY
                            ),
                            destination: CGPoint(
                                x: destination.x - CGFloat(index) * 4,
                                y: destination.y - CGFloat(index) * 4
                            ),
                            presentation: BrowserDownloadFeedbackPolicy.presentation(
                                hasSource: true,
                                hasSidebarDestination: true,
                                reduceMotion: reduceMotion
                            )
                        )
                    }
                }
            }
        }
        .background(
            BrowserDownloadFeedbackWindowIdentityReader(
                identifier: $windowIdentifier
            )
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var visibleEvents: [BrowserDownloadFeedbackEvent] {
        events.filter { event in
            guard event.profileID == profileID else { return false }
            guard event.spaceID == spaceID else { return false }
            guard let windowIdentifier else { return false }
            return event.source.windowIdentifier == windowIdentifier
        }
    }
}

private struct BrowserDownloadFeedbackIcon: View {
    let filename: String
    let source: CGPoint
    let destination: CGPoint
    let presentation: BrowserDownloadFeedbackPresentation

    @State private var hasArrived = false

    var body: some View {
        icon
            .position(position)
            .opacity(opacity)
            .scaleEffect(scale)
            .task {
                await Task.yield()
                switch presentation {
                case .flight:
                    withAnimation(.spring(duration: 0.68, bounce: 0.16)) {
                        hasArrived = true
                    }
                case .destinationFade:
                    withAnimation(.easeOut(duration: 0.24)) {
                        hasArrived = true
                    }
                case .none:
                    break
                }
            }
    }

    private var icon: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(
                systemName: BrowserDownloadFileIconPolicy.systemImage(
                    for: filename
                )
            )
            .font(.system(size: 21, weight: .medium))
            .symbolRenderingMode(.hierarchical)

            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 11, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .tint)
                .offset(x: 3, y: 3)
        }
        .foregroundStyle(.primary)
        .frame(width: 36, height: 36)
        .background(.regularMaterial, in: .rect(cornerRadius: 9))
        .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
    }

    private var position: CGPoint {
        presentation == .flight && !hasArrived ? source : destination
    }

    private var opacity: Double {
        switch presentation {
        case .flight:
            hasArrived ? 0.84 : 1
        case .destinationFade:
            hasArrived ? 0.9 : 0
        case .none:
            0
        }
    }

    private var scale: CGFloat {
        presentation == .destinationFade && !hasArrived ? 0.92 : 1
    }
}
