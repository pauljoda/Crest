import SwiftUI

/// The capsule a notice shows in at the top of a window: its symbol and
/// words, and the one action it may offer.
struct BrowserNoticeView: View {
    let notice: BrowserNotice
    /// How far the capsule stands below the top of the area it shows over.
    var topInset = BrowserRootMetrics.noticeTopInset
    /// How far the capsule keeps from each side of that area, where a narrow
    /// window would otherwise let long words run to its edges.
    var sideInset: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: CrestSpacing.medium) {
            Label(notice.message, systemImage: notice.systemImage)
                .lineLimit(2)
                .multilineTextAlignment(.center)
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
        .frame(minHeight: BrowserRootMetrics.noticeHeight)
        .frame(maxWidth: BrowserRootMetrics.noticeMaximumWidth)
        .fixedSize(horizontal: false, vertical: true)
        .glassEffect(.regular, in: .rect(cornerRadius: BrowserRootMetrics.noticeHeight / 2))
        .shadow(
            color: .black.opacity(
                reduceTransparency ? 0 : CrestOpacity.controlShadow
            ),
            radius: BrowserRootMetrics.noticeShadowRadius,
            y: BrowserRootMetrics.noticeShadowYOffset
        )
        .padding(.horizontal, sideInset)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .top
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
