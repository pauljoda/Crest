import AppKit
import SwiftUI
import XCTest

@testable import Crest

/// Sidebar shortcuts act on their owning window, even after a utility is already open.
@MainActor
final class BrowserSidebarCommandTests: XCTestCase {
    func testFindMovesNativeFocusIntoHistorySearch() async throws {
        let browser = BrowserStore.hostingPages()
        let pages = BrowserPagePool(browser: browser)
        let chrome = BrowserChromeState()
        chrome.presentUtility(.history)
        let host = NSHostingView(
            rootView: BrowserRootView(
                browser: browser, pages: pages, chrome: chrome,
                transientBrowsing: BrowserTransientBrowsingCoordinator(), persistSidebarWidth: { _ in }))
        let frame = CGRect(x: 0, y: 0, width: 1120, height: 720)
        let container = NSView(frame: frame)
        host.frame = frame
        container.addSubview(host)
        let sentinel = NSTextField(string: "Outside browser")
        sentinel.frame = CGRect(x: 500, y: 20, width: 180, height: 24)
        container.addSubview(sentinel)
        let window = NSWindow(
            contentRect: frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = container
        defer {
            window.close()
            pages.reconcile(validTabIDs: [])
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(window.makeFirstResponder(sentinel))
        let actions = BrowserCommandActions(browser: browser, pages: pages, chrome: chrome, windows: nil)
        XCTAssertTrue(actions.canPerform(.findInPage))
        actions.perform(.findInPage)
        for _ in 0..<20 {
            if let editor = window.firstResponder as? NSTextView,
                let field = editor.delegate as? NSTextField, field !== sentinel, field.isDescendant(of: host),
                field.placeholderString == String(localized: BrowserUtilitySurface.history.searchPrompt)
            {
                editor.insertText("history-route-397", replacementRange: NSRange(location: NSNotFound, length: 0))
                XCTAssertEqual(editor.string, "history-route-397")
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Find must move native input focus from the sentinel into the History search field.")
    }

    func testFindUsesTheLoadedPageOutsideHistory() async throws {
        let url = try XCTUnwrap(URL(string: "about:blank"))
        let tab = TabState.Seed(title: "Find page", url: url, placement: .current)
        let space = SpaceState.Seed(name: "Page find", symbol: "globe", accent: .indigo, folders: [], tabs: [tab])
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: tab.id])
        let pages = BrowserPagePool(browser: browser, usesEphemeralWebsiteDataStores: true)
        defer { pages.reconcile(validTabIDs: []) }
        pages.select()
        let page = try XCTUnwrap(pages.activePage)
        for _ in 0..<40 {
            if page.live.documentURL != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertNotNil(page.live.documentURL)
        let chrome = BrowserChromeState()
        let actions = BrowserCommandActions(browser: browser, pages: pages, chrome: chrome, windows: nil)
        XCTAssertTrue(actions.canPerform(.findInPage))
        actions.perform(.findInPage)
        XCTAssertTrue(page.isFindPresented)
        chrome.presentUtility(.archive)
        let previousRequest = page.findFocusRequest
        actions.perform(.findInPage)
        XCTAssertGreaterThan(page.findFocusRequest, previousRequest)
    }

    func testFindIsAvailableForVisibleHistoryWithoutALoadedWebpage() {
        let browser = BrowserStore.hostingPages()
        let chrome = BrowserChromeState()
        let actions = BrowserCommandActions(
            browser: browser, pages: BrowserPagePool(browser: browser), chrome: chrome, windows: nil)
        XCTAssertFalse(actions.canPerform(.findInPage))
        actions.perform(.showHistory)
        XCTAssertTrue(actions.canPerform(.findInPage))
    }

    func testRepeatingEachUtilityCommandClosesOnlyItsOwningWindowPanel() {
        let browser = BrowserStore.hostingPages()
        let pages = BrowserPagePool(browser: browser)
        let otherWindow = BrowserChromeState()
        otherWindow.presentUtility(.history)
        let commands: [(ShortcutCommand, BrowserUtilitySurface)] = [
            (.showHistory, .history), (.showArchive, .archive), (.showDownloads, .downloads),
        ]
        for (command, surface) in commands {
            let chrome = BrowserChromeState(sidebarIsPresented: false)
            let actions = BrowserCommandActions(browser: browser, pages: pages, chrome: chrome, windows: nil)
            actions.perform(command)
            XCTAssertEqual(chrome.utilityPresentation.surface, surface)
            XCTAssertEqual(chrome.columnVisibility, .all)
            actions.perform(command)
            XCTAssertNil(chrome.utilityPresentation.surface)
            XCTAssertEqual(otherWindow.utilityPresentation.surface, .history)
            actions.perform(command)
            XCTAssertEqual(chrome.utilityPresentation.surface, surface)
        }
    }

    func testUtilityCommandShowsAHiddenListAndReplacesADifferentList() {
        let browser = BrowserStore.hostingPages()
        let chrome = BrowserChromeState()
        let actions = BrowserCommandActions(
            browser: browser, pages: BrowserPagePool(browser: browser), chrome: chrome, windows: nil)
        actions.perform(.showHistory)
        chrome.hideSidebar()
        actions.perform(.showHistory)
        XCTAssertEqual(chrome.columnVisibility, .all)
        XCTAssertEqual(chrome.utilityPresentation.surface, .history)
        actions.perform(.showArchive)
        XCTAssertEqual(chrome.utilityPresentation.surface, .archive)
        actions.perform(.showDownloads)
        XCTAssertEqual(chrome.utilityPresentation.surface, .downloads)
    }

    func testFindDoesNotSearchAHiddenOrLockedHistoryList() {
        let browser = BrowserStore.hostingPages()
        let chrome = BrowserChromeState()
        let actions = BrowserCommandActions(
            browser: browser, pages: BrowserPagePool(browser: browser), chrome: chrome, windows: nil)
        actions.perform(.showHistory)
        chrome.hideSidebar()
        XCTAssertFalse(actions.canPerform(.findInPage))
        chrome.showSidebar()
        if let space = browser.shownSpace {
            browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: space.id)
        } else {
            XCTFail("The history command fixture requires a Space.")
        }
        XCTAssertFalse(actions.canPerform(.findInPage))
    }
}
