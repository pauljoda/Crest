import SwiftUI

/// Transport controls for a seekable presentation. The poll lives only while
/// the controls are revealed. Dragging previews a time locally and sends one
/// seek on release, so a slow renderer never drags the thumb backwards.
struct BrowserPictureInPictureScrubber: View {
    // MARK: - Variables

    let source: (any BrowserPagePictureInPictureController)?
    let isRevealed: Bool
    var availabilityChanged: (Bool) -> Void = { _ in }
    @State private var timeline: BrowserPictureInPictureTimeline?
    @State private var isDragging = false
    @State private var preview: Double?
    @State private var seekTask: Task<Void, Never>?
    @State private var revision = 0

    private var visibleSource: ObjectIdentifier? {
        isRevealed ? source.map(ObjectIdentifier.init) : nil
    }

    // MARK: - Actions - Drawing

    var body: some View {
        ZStack {
            if let timeline {
                HStack(spacing: CrestSpacing.extraSmall) {
                    skip("Back 10 Seconds", symbol: "gobackward.10", by: -BrowserPictureInPictureTimeline.skipInterval)
                    Slider(
                        value: Binding(
                            get: { min(timeline.end, max(timeline.start, preview ?? timeline.position)) },
                            set: { position in
                                if isDragging { preview = position } else { seek(to: position, relative: false) }
                            }),
                        in: timeline.start...timeline.end,
                        onEditingChanged: { dragging in
                            isDragging = dragging
                            if !dragging, let preview { seek(to: preview, relative: false) }
                        }
                    )
                    .controlSize(.small)
                    .accessibilityLabel(Text("Playback position"))
                    .accessibilityValue(Text(verbatim: formattedTime(preview ?? timeline.position)))
                    .help(formattedTime(preview ?? timeline.position))
                    skip("Forward 10 Seconds", symbol: "goforward.10", by: BrowserPictureInPictureTimeline.skipInterval)
                }
                .padding(.horizontal, CrestSpacing.extraSmall)
                .padding(.vertical, CrestSpacing.extraExtraSmall)
                .crestGlass(in: Capsule())
                .environment(\.colorScheme, .dark)
            }
        }
        .onChange(of: timeline != nil) { _, available in availabilityChanged(available) }
        .task(id: visibleSource) { await followVideo() }
    }

    private func skip(_ title: LocalizedStringResource, symbol: String, by seconds: Double) -> some View {
        Button {
            seek(to: seconds, relative: true)
        } label: {
            Image(systemName: symbol).accessibilityLabel(Text(title))
        }
        .buttonStyle(CrestChromeButtonStyle.circle())
        .help(String(localized: title))
    }

    private func formattedTime(_ seconds: Double) -> String {
        Duration.seconds(seconds.rounded(.down)).formatted(
            .time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }

    // MARK: - Actions - Playback

    private func followVideo() async {
        guard isRevealed, let source else { return }
        preview = nil
        isDragging = false
        while !Task.isCancelled {
            let version = revision
            let next = await source.timeline(moving: nil)
            guard !Task.isCancelled else { return }
            if version == revision, seekTask == nil {
                if next?.id != timeline?.id {
                    preview = nil
                    isDragging = false
                }
                timeline = next
            }
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
        }
    }

    private func seek(to seconds: Double, relative: Bool) {
        guard seconds.isFinite, let source, let timeline else { return }
        revision += 1
        let version = revision
        let previous = seekTask
        seekTask = Task { @MainActor in
            // Keep quick successive skips ordered at the original player.
            await previous?.value
            let next = await source.timeline(moving: .init(id: timeline.id, seconds: seconds, relative: relative))
            guard version == revision else { return }
            self.timeline = next
            preview = nil
            seekTask = nil
        }
    }
}
