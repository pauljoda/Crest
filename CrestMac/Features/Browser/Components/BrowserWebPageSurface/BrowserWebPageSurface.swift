import SwiftUI

struct BrowserWebPageSurface: View {
    let page: BrowserPage
    let browser: BrowserStore
    let pagePresentation: BrowserPagePresentation
    let isPageActive: Bool
    let focusRestorationGate: BrowserWebFocusRestorationGate

    var body: some View {
        ZStack(alignment: .top) {
            BrowserPlatformWebView(
                page: page,
                isPageActive: isPageActive,
                focusRestorationGate: focusRestorationGate
            )
            .accessibilityLabel(page.title.isEmpty ? "Web page" : page.title)
            .opacity(
                BrowserPageSurfacePolicy.revealsWebContent(
                    committedNavigationCount: page.committedNavigationCount
                ) ? 1 : 0
            )

            BrowserPageLoadingPresentation(page: page)

            BrowserLinkHoverPreview(hover: page.linkHover)

            if page.isFindPresented {
                BrowserFindBar(
                    port: findPort,
                    capabilities: capabilities,
                    isPageActive: isPageActive
                )
                .padding(BrowserWebPageSurfaceMetrics.overlayPadding)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topTrailing
                )
            }

            BrowserWebPageFailureOverlay(
                page: page,
                branding: browser.selectedSpace?.branding,
                pagePresentation: pagePresentation
            )

            BrowserCredentialChrome(
                presentation: BrowserCredentialChromePresentation.resolve(
                    saveCandidate: page.credentialSaveCandidate,
                    fillRequest: page.credentialFillRequest
                ),
                fillPort: credentialFillPort,
                savePort: credentialSavePort,
                browser: browser,
                capabilities: capabilities
            )

            if page.isRegionCapturePresented {
                BrowserRegionCaptureOverlay(page: page)
                    .zIndex(BrowserWebPageSurfaceMetrics.regionCaptureZIndex)
            }

            if let feedback = page.developerCaptureFeedback {
                BrowserDeveloperCaptureFeedbackView(feedback: feedback)
                    .zIndex(BrowserWebPageSurfaceMetrics.feedbackZIndex)
            }
        }
    }

    /// The four questions the find bar asks, bound to this surface's page.
    private var findPort: BrowserFindPort {
        BrowserFindPort(
            find: { query, direction in
                page.find(query, direction: direction)
            },
            query: { page.findQuery },
            matchState: { page.findMatchState },
            focusRequest: { page.findFocusRequest },
            dismiss: page.dismissFind
        )
    }

    /// What a credential fill prompt asks of this surface's page.
    ///
    /// The zoom is carried because this shell anchors the prompt under the
    /// field that raised it, and the page reports that field in its own CSS
    /// pixels. The chrome is a sibling of the web view inside one box, so the
    /// zoom is the only thing between the two.
    private var credentialFillPort: BrowserCredentialFillPort {
        BrowserCredentialFillPort(
            spaceID: page.spaceID,
            contentScale: page.pageZoom,
            siteIconData: page.faviconData,
            fill: { credential, requestID in
                try await page.fillCredential(credential, for: requestID)
            },
            fillGeneratedPassword: { password, requestID in
                try await page.fillGeneratedPassword(password, for: requestID)
            },
            dismiss: page.dismissCredentialFillRequest
        )
    }

    /// What the save prompt asks of this surface's page. This shell makes no
    /// offer to the system's Passwords app, so it binds none.
    private var credentialSavePort: BrowserCredentialSavePort {
        BrowserCredentialSavePort(
            spaceID: page.spaceID,
            presentedCandidateID: { page.credentialSaveCandidate?.id },
            dismiss: page.dismissCredentialSaveCandidate,
            offerToSystemPasswords: nil
        )
    }

    /// What this shell can do: a pointer rests over the chrome and nothing is
    /// aimed at with a finger.
    private var capabilities: BrowserInteractionCapabilities {
        BrowserInteractionCapabilities()
    }
}

private struct BrowserPageLoadingPresentation: View {
    let page: BrowserPage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if showsInitialStatus {
                    initialStatus
                }
            }
            .overlay(alignment: .top) {
                loadingProgress
            }
            .allowsHitTesting(false)
    }

    private var initialStatus: some View {
        VStack(spacing: BrowserWebPageSurfaceMetrics.initialLoadingSpacing) {
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
            openingLabel
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("browser-initial-loading-status")
    }

    private var loadingProgress: some View {
        Rectangle()
            .fill(.tint)
            .frame(height: BrowserWebPageSurfaceMetrics.loadingProgressHeight)
            .scaleEffect(x: progress, anchor: .leading)
            .opacity(isNavigating ? 1 : 0)
            .animation(
                BrowserVisualAccessibilityPolicy.animation(
                    CrestMotion.loadingProgress,
                    reduceMotion: reduceMotion
                ),
                value: progress
            )
            .accessibilityHidden(true)
    }

    private var openingLabel: Text {
        guard let host = page.displayURL?.host(), !host.isEmpty else {
            return Text(
                "Opening page…",
                comment: "Initial status while a web page begins navigating."
            )
        }
        return Text(
            "Opening \(host)…",
            comment: "Initial page loading status; the value is the destination host."
        )
    }

    private var isNavigating: Bool {
        BrowserPageSurfacePolicy.isNavigating(
            isLoading: page.isLoading,
            hasPendingNavigation: page.pendingNavigationURL != nil,
            committedNavigationCount: page.committedNavigationCount
        )
    }

    private var hasFailure: Bool {
        page.navigationFailure != nil || page.webContentFailureMessage != nil
    }

    private var showsInitialStatus: Bool {
        BrowserPageSurfacePolicy.showsInitialLoadingStatus(
            isNavigating: isNavigating,
            committedNavigationCount: page.committedNavigationCount,
            hasFailure: hasFailure
        )
    }

    private var progress: CGFloat {
        BrowserPageSurfacePolicy.loadingProgress(
            estimatedProgress: page.estimatedProgress,
            isNavigating: isNavigating
        )
    }
}
