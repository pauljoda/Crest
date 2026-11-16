import SwiftUI

/// The capsule a notice shows in at the top of a window, as wide as its
/// symbol, words and the one action it may offer, in the window's top trailing
/// corner or, on a phone, the middle of its top.
struct BrowserNoticeView: View {
    let notice: BrowserNotice
    /// Where in the area it shows over the capsule stands.
    var alignment = Alignment.topTrailing
    /// How far the capsule stands below the top of that area.
    var topInset = BrowserRootMetrics.noticeInset
    /// How far the capsule keeps from each side of that area.
    var sideInset = BrowserRootMetrics.noticeInset

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: CrestSpacing.medium) {
            Label(notice.message, systemImage: notice.systemImage)
                .lineLimit(2)
                .accessibilityLabel(notice.accessibilityLabel ?? notice.message)
            if let action = notice.action {
                Button(action.title, action: action.perform)
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("notice-action")
            }
        }
        .font(.callout.weight(.semibold))
        .padding(
            .horizontal,
            BrowserRootMetrics.noticeHorizontalPadding
        )
        // Words that wrap keep clear of the capsule's top and bottom.
        .padding(.vertical, CrestSpacing.small)
        .frame(minHeight: BrowserRootMetrics.noticeHeight)
        .fixedSize(horizontal: false, vertical: true)
        .crestFloatingFlyoutStyle(in: .rect(cornerRadius: BrowserRootMetrics.noticeHeight / 2))
        .shadow(
            color: .black.opacity(
                reduceTransparency ? 0 : CrestOpacity.controlShadow
            ),
            radius: BrowserRootMetrics.noticeShadowRadius,
            y: BrowserRootMetrics.noticeShadowYOffset
        )
        // The capsule fits its words, which wrap once it is this wide.
        .frame(maxWidth: BrowserRootMetrics.noticeMaximumWidth, alignment: alignment)
        .padding(.horizontal, sideInset)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: alignment
        )
        .padding(.top, topInset)
        .allowsHitTesting(notice.action != nil)
        .accessibilityElement(children: notice.action == nil ? .combine : .contain)
        .accessibilityAddTraits(notice.action == nil ? .isStaticText : [])
        .transition(
            reduceMotion
                ? .opacity
                : .move(edge: .top).combined(with: .opacity)
        )
        .zIndex(BrowserRootMetrics.feedbackZIndex)
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserNoticeView(notice: .urlCopied).padding().frame(width: 320, height: 150)
    }
#endif
