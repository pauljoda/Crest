import SwiftUI

struct BrowserWebContentView: View {
    let page: BrowserPage
    let browser: BrowserStore
    let pages: BrowserPagePool

    @Environment(\.browserWebFocusRestorationGate)
    private var browserFocusRestorationGate

    var body: some View {
        VStack(spacing: 0) {
            BrowserWebPageDebuggerBanner(page: page, pages: pages)

            GeometryReader { geometry in
                let layout = BrowserDeveloperViewportLayout(
                    viewport: page.developerViewport,
                    available: geometry.size
                )
                BrowserWebPageSurface(
                    page: page,
                    browser: browser,
                    pagePresentation: pagePresentation,
                    isPageActive: pages.activePage === page,
                    focusRestorationGate: focusRestorationGate
                )
                .frame(width: layout.contentSize.width, height: layout.contentSize.height)
                .scaleEffect(layout.scale)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            }
        }
        .modifier(
            BrowserPageToolbarHost {
                if pages.activePage === page, isSelectedSpace,
                    !page.readerModeState.isActive, page.translation.showsToolbar
                {
                    BrowserTranslationToolbar(translation: page.translation)
                }
                if page.isDeveloperModeEnabled {
                    BrowserDeveloperToolbar(
                        page: page, browser: browser, pages: pages,
                        permissionCenter: pages.permissionCenter
                    )
                }
            }
        )
        .modifier(
            BrowserTranslationHost(
                translation: page.translation, webView: page.webView,
                isActive: pages.activePage === page && isSelectedSpace,
                isLoading: page.isLoading,
                isReaderActive: page.readerModeState.isActive
            )
        )
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
            get: { isSelectedSpace && page.isChromeWebStoreInstallPresented },
            set: { isPresented in
                if !isPresented {
                    page.dismissChromeWebStoreInstall()
                }
            }
        )
    }

    private var mozillaAddonsInstallPresentation: Binding<Bool> {
        Binding(
            get: { isSelectedSpace && page.mozillaAddonsInstall.isPresented },
            set: { isPresented in
                if !isPresented {
                    page.mozillaAddonsInstall.dismiss()
                }
            }
        )
    }

    private var isSelectedSpace: Bool {
        browser.selectedSpace?.id == page.spaceID && browser.selectedSpace?.profile.id == page.profileID
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
