import SwiftUI

/// The seam between the saved run and the current one, on every shell.
///
/// Pointer-only shells reveal Clear on hover, and holding Option turns it into
/// Clear All. Touch shells center its hit target on the line, using the saved
/// drop band as the space above it.
struct BrowserCurrentTabsDivider: View {
    // MARK: - Static Variables

    /// The side of the clear control's hit target on a touch shell.
    private static var touchTarget: CGFloat { 44 }

    // MARK: - Variables

    let capabilities: BrowserInteractionCapabilities
    var hasSavedTabsEndBand = false
    /// Whether the shell is currently in the state that reveals the control —
    /// a pointer resting somewhere over the list.
    var showsClearAction = false
    /// Whether an open tab other than the shown one is left to clear.
    let canClearOthers: Bool
    /// Whether any open tab is left to clear.
    let canClearAll: Bool
    /// Archives the open tabs but the shown one.
    let clearOthers: () -> Void
    /// Archives every open tab.
    let clearAll: () -> Void
    /// How wide the clear control's label draws, which the line stops short
    /// of.
    @State private var clearLabelWidth: CGFloat = 0
    /// Whether Option is held, which turns Clear into Clear All.
    @State private var isOptionHeld = false
    @Environment(\.displayScale) private var displayScale

    // MARK: - Actions - Drawing

    private var metrics: BrowserSidebarTabListMetrics {
        capabilities.tabListMetrics
    }

    var body: some View {
        Group {
            if revealsOnHoverOnly {
                ZStack(alignment: .trailing) {
                    line
                    clearButton
                }
                .padding(
                    .vertical,
                    BrowserDeviceAppearanceStore.shared.sidebarSpacing.gap(metrics.dividerVerticalInset)
                )
                .onOptionKeyChange { isOptionHeld = $0 }
            } else {
                line
                    .overlay(alignment: .trailing) { clearButton }
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
            .padding(.trailing, showsClearButton ? clearActionOcclusion : 0)
    }

    private var clearButton: some View {
        Button(action: clearsAll ? clearAll : clearOthers) {
            HStack(spacing: CrestSpacing.extraSmall) {
                if revealsOnHoverOnly { Text(clearsAll ? "Clear All" : "Clear") }
                Image(systemName: "archivebox")
                Image(systemName: "arrow.down")
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                clearLabelWidth = width
            }
            .frame(
                minWidth: revealsOnHoverOnly ? nil : Self.touchTarget,
                minHeight: revealsOnHoverOnly ? nil : Self.touchTarget
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .fixedSize()
        .opacity(showsClearButton ? 1 : 0)
        .disabled(!canClear || !showsClearButton)
        .accessibilityHidden(!showsClearButton)
        .accessibilityLabel(clearsAll ? "Clear All Tabs" : "Clear Other Tabs")
        .accessibilityHint(clearsAll ? "Moves all open tabs to Archive" : "Moves the other open tabs to Archive")
        .accessibilityAction(named: "Clear All Tabs") {
            if canClearAll { clearAll() }
        }
    }

    /// Whether the control clears every open tab, the shown one too: on a
    /// pointer-only shell while Option is held.
    private var clearsAll: Bool {
        revealsOnHoverOnly && isOptionHeld
    }

    /// Whether what the control clears now holds anything.
    private var canClear: Bool {
        clearsAll ? canClearAll : canClearOthers
    }

    /// How much of the line's trailing end the clear control takes: its
    /// label, centered in its hit target, and the gap before it.
    private var clearActionOcclusion: CGFloat {
        let target = revealsOnHoverOnly ? clearLabelWidth : max(Self.touchTarget, clearLabelWidth)
        return (target + clearLabelWidth) / 2 + metrics.clearActionGap
    }

    private var touchSpacing: CGFloat {
        max(22, metrics.dividerVerticalInset)
    }

    private var showsClearButton: Bool {
        !revealsOnHoverOnly || (showsClearAction && canClear)
    }

    private var revealsOnHoverOnly: Bool {
        capabilities.revealsRowControlsOnHoverOnly
    }
}

extension View {
    /// Follows whether Option is held, where the platform reports modifier
    /// keys to a view. iPhone and iPad never report one.
    fileprivate func onOptionKeyChange(_ action: @escaping (Bool) -> Void) -> some View {
        #if os(macOS)
            onModifierKeysChanged(mask: .option, initial: true) { _, held in action(held.contains(.option)) }
        #else
            self
        #endif
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserCurrentTabsDivider(
            capabilities: BrowserInteractionCapabilities(), showsClearAction: true, canClearOthers: true,
            canClearAll: true, clearOthers: {}, clearAll: {}
        ).padding().frame(width: 320)
    }
#endif
