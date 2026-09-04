import SwiftUI

struct BrowserWebContentView: View {
    let page: BrowserPage
    let browser: BrowserStore
    let pages: BrowserPagePool

    @Environment(\.browserWebFocusRestorationGate)
    private var browserFocusRestorationGate

    var body: some View {
        VStack(spacing: 0) {
            if page.isDeveloperModeEnabled {
                BrowserDeveloperToolbar(
                    page: page,
                    browser: browser,
                    pages: pages,
                    permissionCenter: pages.permissionCenter
                )
            }

            BrowserWebPageDebuggerBanner(page: page, pages: pages)

            BrowserWebPageSurface(
                page: page,
                browser: browser,
                pagePresentation: pagePresentation,
                isPageActive: pages.activePage === page,
                focusRestorationGate: focusRestorationGate
            )
        }
        .onChange(of: page.developerCaptureFeedbackRevision) { _, revision in
            dismissDeveloperFeedback(after: revision)
        }
        .sheet(isPresented: chromeWebStoreInstallPresentation) {
            BrowserChromeWebStoreInstallView(page: page)
        }
        .sheet(isPresented: mozillaAddonsInstallPresentation) {
            BrowserMozillaAddonsInstallView(
                session: page.mozillaAddonsInstall
            )
        }
    }

    private var focusRestorationGate: BrowserWebFocusRestorationGate {
        BrowserWebFocusRestorationGate(
            browserChromeOwnsFocus:
                browserFocusRestorationGate.browserChromeOwnsFocus,
            pageChromeOwnsFocus:
                page.isFindPresented
                || page.credentialFillRequest != nil
                || page.credentialSaveCandidate != nil
                || page.isRegionCapturePresented
                || page.isChromeWebStoreInstallPresented
                || page.mozillaAddonsInstall.isPresented
                || page.navigationFailure != nil
                || page.webContentFailureMessage != nil
        )
    }

    private var pagePresentation: BrowserPagePresentation {
        BrowserPagePresentationPolicy.resolve(
            BrowserPagePresentationInput(
                selection: .webPage,
                hasActivePage: true,
                hasNavigationFailure: page.navigationFailure != nil,
                hasProcessFailure: page.webContentFailureMessage != nil,
                unloadedBehavior: .remainUnloaded
            )
        )
    }

    private var chromeWebStoreInstallPresentation: Binding<Bool> {
        Binding(
            get: { page.isChromeWebStoreInstallPresented },
            set: { isPresented in
                if !isPresented {
                    page.dismissChromeWebStoreInstall()
                }
            }
        )
    }

    private var mozillaAddonsInstallPresentation: Binding<Bool> {
        Binding(
            get: { page.mozillaAddonsInstall.isPresented },
            set: { isPresented in
                if !isPresented {
                    page.mozillaAddonsInstall.dismiss()
                }
            }
        )
    }

    private func dismissDeveloperFeedback(after revision: Int) {
        guard revision > 0 else { return }
        Task { @MainActor in
            try? await Task.sleep(
                for: BrowserDeveloperCaptureFeedbackPolicy.displayDuration
            )
            guard page.developerCaptureFeedbackRevision == revision else { return }
            page.dismissDeveloperCaptureFeedback()
        }
    }
}
