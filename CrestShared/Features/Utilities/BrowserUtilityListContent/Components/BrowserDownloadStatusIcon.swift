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
