import SwiftUI

/// The seam between the saved run and the current one, on every shell.
///
/// Pointer-only shells reveal Tidy and Clear on hover. Touch shells center
/// their hit targets on the line, using the saved drop band as the space above
/// it.
struct BrowserCurrentTabsDivider: View {
    let capabilities: BrowserInteractionCapabilities
    var hasSavedTabsEndBand = false
    /// Whether the shell is currently in the state that reveals the control —
    /// a pointer resting somewhere over the list.
    var showsClearAction = false
    /// Whether there is anything left to clear.
    let canClear: Bool
    let clear: () -> Void
    /// Whether the on-device model can run and enough loose tabs are open to tidy.
    var canTidy = false
    var tidy: () async throws -> Void = {}
    /// Readies the model when Tidy shows, so pressing it starts sooner.
    var prepareTidy: () -> Void = {}
    @State private var isTidying = false
    @State private var tidyFailed = false
    @Environment(\.displayScale) private var displayScale

    private var metrics: BrowserSidebarTabListMetrics {
        capabilities.tabListMetrics
    }

    var body: some View {
        Group {
            if revealsOnHoverOnly {
                ZStack(alignment: .trailing) {
                    line
                    controls
                }
                .padding(.vertical, metrics.dividerVerticalInset)
            } else {
                line
                    .overlay(alignment: .trailing) { controls }
                    .padding(
                        .top,
                        hasSavedTabsEndBand ? max(0, touchSpacing - metrics.savedSectionEndBandHeight) : touchSpacing
                    )
                    .padding(.bottom, touchSpacing)
            }
        }
        .padding(.horizontal, metrics.dividerHorizontalInset)
    }

    private var line: some View {
        Divider()
            .frame(height: 1 / displayScale)
            .padding(.trailing, lineOcclusionWidth)
    }

    private var controls: some View {
        HStack(spacing: CrestSpacing.small) {
            if showsTidyButton { tidyButton }
            clearButton
        }
    }

    private var tidyButton: some View {
        Button(action: startTidying) {
            HStack(spacing: 4) {
                if revealsOnHoverOnly { Text(tidyFailed ? "Couldn't Tidy" : "Tidy") }
                if isTidying {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: tidyFailed ? "exclamationmark.triangle" : "wand.and.sparkles")
                }
            }
            .frame(minWidth: revealsOnHoverOnly ? nil : 44, minHeight: revealsOnHoverOnly ? nil : 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .fixedSize()
        .disabled(isTidying)
        .onAppear(perform: prepareTidy)
        .accessibilityLabel(tidyFailed ? "Couldn't Tidy Open Tabs" : "Tidy Open Tabs")
        .accessibilityHint("Groups open tabs under headers")
    }

    private var clearButton: some View {
        Button(action: clear) {
            HStack(spacing: 4) {
                if revealsOnHoverOnly { Text("Clear") }
                Image(systemName: "archivebox")
                Image(systemName: "arrow.down")
            }
            .frame(minWidth: revealsOnHoverOnly ? nil : 44, minHeight: revealsOnHoverOnly ? nil : 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .fixedSize()
        .opacity(showsClearButton ? 1 : 0)
        .disabled(!canClear || !showsClearButton)
        .accessibilityHidden(!showsClearButton)
        .accessibilityLabel("Clear Open Tabs")
        .accessibilityHint("Moves all current tabs to Archive")
    }

    private func startTidying() {
        isTidying = true
        tidyFailed = false
        Task {
            do {
                try await tidy()
                isTidying = false
            } catch {
                isTidying = false
                tidyFailed = true
                try? await Task.sleep(for: .seconds(4))
                tidyFailed = false
            }
        }
    }

    private var touchSpacing: CGFloat {
        max(22, metrics.dividerVerticalInset)
    }

    private var lineOcclusionWidth: CGFloat {
        (showsClearButton ? metrics.clearActionOcclusionWidth : 0)
            + (showsTidyButton ? metrics.tidyActionOcclusionWidth : 0)
    }

    private var showsClearButton: Bool {
        !revealsOnHoverOnly || (showsClearAction && canClear)
    }

    /// Tidy shows where Clear does, and stays while it works or reports a failure.
    private var showsTidyButton: Bool {
        isTidying || tidyFailed || (canTidy && (!revealsOnHoverOnly || showsClearAction))
    }

    private var revealsOnHoverOnly: Bool {
        capabilities.revealsRowControlsOnHoverOnly
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserCurrentTabsDivider(
            capabilities: BrowserInteractionCapabilities(), showsClearAction: true, canClear: true, clear: {},
            canTidy: true
        ).padding().frame(width: 320)
    }
#endif
