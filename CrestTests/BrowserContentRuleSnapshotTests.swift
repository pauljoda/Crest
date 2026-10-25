import Foundation
import WebKit
import XCTest
import os

#if os(macOS)
    @testable import Crest
#else
    @testable import CrestMobile
#endif

@MainActor
final class BrowserContentRuleSnapshotTests: XCTestCase {
    // MARK: - Actions - Native filtering

    func testBundledSnapshotCompilesAndHidesDynamicAdsInAnIsolatedLaunch() async throws {
        let core = CrestCore()
        let environment = BrowserLaunchEnvironment(values: ["CREST_ISOLATED_SESSION": "1"], isXCTestRuntime: false)
        let provider = BrowserContentRuleListProvider.forLaunch(core: core, launchEnvironment: environment)
        let lists = try await provider.balancedRuleLists()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        for list in lists { configuration.userContentController.add(list) }
        let page = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        page.loadHTMLString(
            "<!doctype html><html><body><p id='article'>Article</p><div id='AdBar'>Advertisement</div></body></html>",
            baseURL: URL(string: "https://example.org"))
        var ready = false
        for _ in 0..<200 {
            if (try? await page.evaluateJavaScript(
                "document.readyState === 'complete' && !!document.getElementById('AdBar')")) as? Bool == true
            {
                ready = true
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(ready)
        let hidden = try await page.evaluateJavaScript(
            "getComputedStyle(document.getElementById('AdBar')).display === 'none'")
        XCTAssertEqual(hidden as? Bool, true)
        _ = try await page.evaluateJavaScript(
            "document.body.insertAdjacentHTML('beforeend', '<div id=AdContainerTop>Dynamic ad</div>'); true")
        var dynamicHidden = false
        for _ in 0..<100 {
            dynamicHidden =
                (try await page.evaluateJavaScript(
                    "getComputedStyle(document.getElementById('AdContainerTop')).display === 'none'")) as? Bool == true
            if dynamicHidden { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let contentVisible = try await page.evaluateJavaScript(
            "getComputedStyle(document.getElementById('article')).display !== 'none'")
        XCTAssertTrue(dynamicHidden)
        XCTAssertEqual(contentVisible as? Bool, true)
    }

    func testRefreshPublishesCompiledRulesAndUsesTheAcceptedCacheOffline() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "crest-rule-publication-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try XCTUnwrap(WKContentRuleListStore(url: directory.appendingPathComponent("compiled")))
        let updates = BrowserContentRuleListUpdates(
            cacheURL: directory.appendingPathComponent("snapshot.json.gz"), session: makeSession())
        let archive = try candidateArchive()
        SnapshotURLProtocol.state.withLock { $0 = .init(data: archive) }
        let compiler = SnapshotCompiler()
        let provider = BrowserContentRuleListProvider(
            core: CrestCore(), ruleListStore: store, compiler: compiler, updates: updates)
        _ = try await provider.balancedRuleLists()
        _ = try await provider.refreshedRuleLists()
        XCTAssertEqual(updates.cachedSnapshot(), archive)
        XCTAssertEqual(compiler.identifiers.count, 2)
        XCTAssertNotEqual(compiler.identifiers.first, compiler.identifiers.last)
        let nextCompiler = SnapshotCompiler()
        let offline = BrowserContentRuleListProvider(
            core: CrestCore(), ruleListStore: store, compiler: nextCompiler, updates: updates)
        _ = try await offline.balancedRuleLists()
        XCTAssertEqual(nextCompiler.identifiers, [try XCTUnwrap(compiler.identifiers.last)])
        XCTAssertEqual(SnapshotURLProtocol.state.withLock { $0.requests }, 1)
    }

    func testNamedIsolatedProfilesCompileIntoSeparateRuleStores() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("crest-rule-isolation-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let environment = BrowserLaunchEnvironment(
            values: ["CREST_ISOLATED_SESSION": "1", "CREST_ISOLATED_PERSISTENCE_ID": "blocking-test"],
            isXCTestRuntime: false)
        let firstDirectory = directory.appendingPathComponent("first")
        let secondDirectory = directory.appendingPathComponent("second")
        let firstCore = try CrestCore(configuration: AppConfiguration(storageDirectory: firstDirectory.path))
        let secondCore = try CrestCore(configuration: AppConfiguration(storageDirectory: secondDirectory.path))
        let first = BrowserContentRuleListProvider.forLaunch(core: firstCore, launchEnvironment: environment)
        let second = BrowserContentRuleListProvider.forLaunch(core: secondCore, launchEnvironment: environment)
        let lists = try await first.balancedRuleLists()
        let secondStore = try XCTUnwrap(
            WKContentRuleListStore(url: secondDirectory.appendingPathComponent("ContentRules")))
        let before = await BrowserContentRuleListCompiler.availableIdentifiers(store: secondStore)
        XCTAssertTrue(before.isEmpty)
        let secondLists = try await second.balancedRuleLists()
        XCTAssertEqual(secondLists.map(\.identifier), lists.map(\.identifier))
        let after = await BrowserContentRuleListCompiler.availableIdentifiers(store: secondStore)
        XCTAssertEqual(after, lists.map(\.identifier))
    }

    func testRefreshDoesNotReplaceWorkingRulesOrCacheWhenCompilationFails() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("crest-rule-update-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try XCTUnwrap(WKContentRuleListStore(url: directory.appendingPathComponent("compiled")))
        let updates = BrowserContentRuleListUpdates(
            cacheURL: directory.appendingPathComponent("snapshot.json.gz"), session: makeSession())
        let archive = try candidateArchive()
        SnapshotURLProtocol.state.withLock { $0 = .init(data: archive) }
        let compiler = SnapshotCompiler()
        let provider = BrowserContentRuleListProvider(
            core: CrestCore(), ruleListStore: store, compiler: compiler, updates: updates)
        _ = try await provider.balancedRuleLists()
        compiler.fail = true
        do {
            _ = try await provider.refreshedRuleLists()
            XCTFail("Compilation should fail")
        } catch {}
        XCTAssertNil(updates.cachedSnapshot())
        let before = compiler.identifiers.count
        _ = try await provider.balancedRuleLists()
        XCTAssertEqual(compiler.identifiers.count, before)
        XCTAssertEqual(SnapshotURLProtocol.state.withLock { $0.requests }, 1)
    }

    func testRefreshRateLimitsSuccessAndFailureAndPersistsOnlyAcceptedData() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("crest-rule-refresh-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let updates = BrowserContentRuleListUpdates(
            cacheURL: directory.appendingPathComponent("snapshot.json.gz"), session: makeSession())
        let archive = try candidateArchive()
        SnapshotURLProtocol.state.withLock { $0 = .init(data: archive) }
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let first = try await updates.downloadIfDue(now: now)
        XCTAssertEqual(first, archive)
        XCTAssertNil(updates.cachedSnapshot())
        try updates.accept(archive, now: now)
        XCTAssertEqual(updates.cachedSnapshot(), archive)
        let early = try await updates.downloadIfDue(now: now.addingTimeInterval(3600))
        XCTAssertNil(early)
        SnapshotURLProtocol.state.withLock { $0.status = 503 }
        do {
            _ = try await updates.downloadIfDue(now: now.addingTimeInterval(86400))
            XCTFail("Failed responses cannot update rules")
        } catch {}
        let retry = try await updates.downloadIfDue(now: now.addingTimeInterval(86460))
        XCTAssertNil(retry)
        XCTAssertEqual(updates.cachedSnapshot(), archive)
        XCTAssertEqual(SnapshotURLProtocol.state.withLock { $0.requests }, 2)
    }

    // MARK: - Actions - Fixtures

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SnapshotURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func candidateArchive() throws -> Data {
        try XCTUnwrap(
            Data(
                base64Encoded:
                    "H4sIAAAAAAAA/02MwQoCMQxEf2WJNzHiVX9FPJQ2LoXQliQVltJ/37henNtj3syAD4nmWuCx3G//uSwgnUm9eA4wyetK4jCgC+M7sx0I1zNMd0O034u7W6NvE1UxZW0cNiy1ELimxBStHstTFFLD3lIwShgSzPmaO/usE1OSAAAA"
            ))
    }
}

@MainActor
private final class SnapshotCompiler: BrowserContentRuleListCompiling {
    // MARK: - Variables

    var fail = false
    var identifiers: [String] = []

    // MARK: - Actions - Compilation

    func compile(identifiers: [String], sources: [String], store: WKContentRuleListStore) async throws
        -> [WKContentRuleList]
    {
        self.identifiers += identifiers
        if fail { throw URLError(.cannotDecodeContentData) }
        return []
    }
}

private final class SnapshotURLProtocol: URLProtocol, @unchecked Sendable {
    // MARK: - Static Variables

    static let state = OSAllocatedUnfairLock(initialState: Response(data: Data()))

    // MARK: - Types

    struct Response {
        var data: Data
        var status = 200
        var requests = 0
    }

    // MARK: - Actions - Requests

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = Self.state.withLock { state in
            state.requests += 1
            return state
        }
        guard let url = request.url,
            let http = HTTPURLResponse(
                url: url, statusCode: response.status, httpVersion: nil,
                headerFields: ["Content-Length": String(response.data.count)])
        else { return }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
