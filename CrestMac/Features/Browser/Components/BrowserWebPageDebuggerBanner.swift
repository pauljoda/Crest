import SwiftUI

/// Says out loud that an extension is driving this page, and offers the way out.
///
/// A `chrome.debugger` session is invisible from inside the page: the extension
/// evaluates in the page's own world, so nothing about the tab looks different
/// while it reads what is typed there. The banner is the only standing signal
/// that it is happening, so it takes layout space above the page rather than
/// floating over content the extension is already reading.
struct BrowserWebPageDebuggerBanner: View {
    let page: BrowserPage
    let pages: BrowserPagePool

    @Environment(BrowserExtensionDebuggerSessionStore.self)
    private var debuggerSessions: BrowserExtensionDebuggerSessionStore?

    var body: some View {
        if let session = controllingSession {
            HStack(spacing: CrestSpacing.small) {
                Image(systemName: "eye.trianglebadge.exclamationmark.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("\(Text(verbatim: session.displayName)) is controlling this tab")
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: CrestSpacing.small)
                Button(String(localized: "Stop")) {
                    debuggerSessions?.cancel(target: session.target)
                }
                .controlSize(.small)
            }
            .padding(.horizontal, CrestSpacing.medium)
            .frame(height: bannerHeight)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)
            .overlay(alignment: .bottom) { Divider() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("browser.page.debuggerBanner")
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var bannerHeight: CGFloat { 32 }

    /// The attached session whose bound tab is the one this view is presenting.
    ///
    /// Matching goes through the page provider rather than a tab identifier the
    /// view carries: the page pool is the only thing that knows which `TabID` a
    /// resident page answers to, and a banner shown above the wrong tab would
    /// be worse than none.
    private var controllingSession: BrowserExtensionDebuggerSession? {
        debuggerSessions?.sessions.first { session in
            session.phase == .attached && session.target.spaceID == page.spaceID
                && pages.extensionWebView(for: session.target.tabID, in: session.target.spaceID)
                    === page.webView
        }
    }
}
