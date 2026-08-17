import SwiftUI

struct BrowserWebContentView: View {
    let page: BrowserPage
    let browser: BrowserStore
    let pages: BrowserPagePool

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

            BrowserWebPageSurface(
                page: page,
                browser: browser,
                pagePresentation: pagePresentation
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
