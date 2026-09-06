import Foundation

struct BrowserModifiedLinkRegistration {
    let tab: BrowserTab
    let space: BrowserSpace
    let session: BrowserSession
}

struct BrowserBackgroundPageUpdate {
    let tabID: TabID
    let assignment: BrowserSpaceRuntimeAssignment
    let url: URL?
    let title: String
    let faviconData: Data?
    let iconAccent: BrowserTabIconAccent?
    let estimatedProgress: Double
    let isLoading: Bool
    let readerModeState: BrowserReaderModeState
    let completedNavigationURL: URL?
    let processTerminationCount: Int
}

@MainActor
struct BrowserBackgroundPageSnapshot: Equatable {
    let url: URL?
    let title: String
    let faviconData: Data?
    let iconAccent: BrowserTabIconAccent?
    let estimatedProgress: Double
    let isLoading: Bool
    let readerModeState: BrowserReaderModeState
    let completedNavigationCount: Int
    let processTerminationCount: Int
    let hasNavigationFailure: Bool

    init(page: BrowserPlatformPage) {
        url = page.displayURL
        let pageTitle: String? = page.title
        title = page.navigationFailure?.displayHost ?? pageTitle ?? page.displayURL?.host() ?? ""
        faviconData = page.faviconData
        iconAccent = page.siteThemeIconAccent
        estimatedProgress = page.estimatedProgress
        isLoading = page.isLoading
        readerModeState = page.readerModeState
        completedNavigationCount = page.completedNavigationCount
        #if os(macOS)
            processTerminationCount = page.processTerminationCount
        #else
            processTerminationCount = 0
        #endif
        hasNavigationFailure = page.navigationFailure != nil
    }
}
