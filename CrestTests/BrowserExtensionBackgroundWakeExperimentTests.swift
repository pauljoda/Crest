import AppKit
import OSLog
import WebKit
import XCTest

@testable import Crest

/// Measures whether a truthful `tabs` event restarts an extension's background
/// service worker after WebKit has stopped it.
///
/// The reading has two halves that have to agree. The fixture records its own
/// worker starts and the events it received, each stamped with `Date.now()`,
/// so a worker that started *at* the event is distinguishable from an event
/// that sat queued until something else started one. Each run also stamps the
/// unified log, so the same moments can be read against WebKit's own
/// `Created service worker`, `WebPageProxy::close` and `terminateWorker` lines
/// — see `Documentation/WebKitExtensionWorkerReport.md` for the readings these
/// runs produced and for the state they could not reach.
///
/// Skipped unless asked for: each run idles past WebKit's background unload,
/// which no ordinary suite should spend.
@MainActor
final class BrowserExtensionBackgroundWakeExperimentTests: XCTestCase {
    private final class PageProviderSpy: BrowserExtensionPageProviding {
        var webViews: [TabID: WKWebView] = [:]

        func extensionWebView(
            for tabID: TabID,
            in spaceID: SpaceID
        ) -> WKWebView? {
            webViews[tabID]
        }

        func extensionReaderModeState(
            for tabID: TabID,
            in spaceID: SpaceID
        ) -> BrowserReaderModeState {
            .unavailable
        }

        func setExtensionReaderModeActive(
            _ isActive: Bool,
            for tabID: TabID,
            in spaceID: SpaceID
        ) async throws {
            throw BrowserReaderModeError.articleUnavailable
        }

        func extensionWindowGeometry(
            in spaceID: SpaceID
        ) -> BrowserExtensionWindowGeometry {
            .unavailable
        }

        func prepareExtensionSelection(session: BrowserSession) {}

        func select(session: BrowserSession) {}
    }

    private enum Stimulus: String {
        case none
        case changedProperties
        case openedTab
    }

    /// One run's record, as the extension itself wrote it.
    private struct Reading {
        let store: String
        let dispatchedAt: Double

        private var contents: [String: Any] {
            (try? JSONSerialization.jsonObject(with: Data(store.utf8)))
                as? [String: Any] ?? [:]
        }

        /// Wall-clock milliseconds, one per time the worker script ran.
        var starts: [Double] {
            (contents["starts"] as? [Any] ?? []).compactMap {
                ($0 as? NSNumber)?.doubleValue
            }
        }

        func values(for key: String) -> [String] {
            (contents[key] as? [Any] ?? []).map { String(describing: $0) }
        }
    }

    /// Past the point where WebKit unloads background content it considers
    /// idle, measured at exactly 30 seconds after the load in every run here.
    private static let pastBackgroundUnload = Duration.seconds(90)

    private static let log = Logger(
        subsystem: "com.pauldavis.crest.wake-experiment",
        category: "probe"
    )

    // MARK: - Runs

    /// A redundant property change carrying the tab's real current values.
    /// This is the shape a popup warm-up could dispatch without inventing
    /// anything, so it is the one worth knowing about.
    func testTabPropertyEventRestartsAnUnloadedBackground() async throws {
        let reading = try await run(
            label: "properties",
            idle: Self.pastBackgroundUnload,
            stimulus: .changedProperties
        )
        assertRestarted(reading, recording: "updated")
    }

    func testOpenedTabEventRestartsAnUnloadedBackground() async throws {
        let reading = try await run(
            label: "opened",
            idle: Self.pastBackgroundUnload,
            stimulus: .openedTab
        )
        assertRestarted(reading, recording: "created")
    }

    /// The control. A worker start that showed up here would mean the wake
    /// readings measure the clock rather than the event — including the
    /// readback, which opens one of the extension's own pages.
    func testAnUnloadedBackgroundStaysStoppedWithoutAnEvent() async throws {
        let reading = try await run(
            label: "control",
            idle: Self.pastBackgroundUnload,
            stimulus: .none
        )
        XCTAssertEqual(
            reading.starts.count,
            1,
            """
            The background restarted itself with nothing dispatched to it, so \
            the wake runs prove nothing. Reading: \(reading.store)
            """
        )
        XCTAssertTrue(
            reading.values(for: "updated").isEmpty
                && reading.values(for: "created").isEmpty,
            "The fixture recorded an event nobody sent. \(reading.store)"
        )
    }

    private func assertRestarted(_ reading: Reading, recording key: String) {
        XCTAssertEqual(
            reading.starts.count,
            2,
            """
            A truthful tab event did not restart the stopped background \
            worker. Reading: \(reading.store)
            """
        )
        XCTAssertGreaterThan(
            reading.starts.last ?? 0,
            reading.dispatchedAt,
            "The second worker start predates the event. \(reading.store)"
        )
        XCTAssertEqual(
            reading.values(for: key).count,
            1,
            """
            The restarted worker did not receive the event that restarted it, \
            so the wake carries no delivery. Reading: \(reading.store)
            """
        )
    }

    // MARK: - Harness

    private func run(
        label: String,
        idle: Duration,
        stimulus: Stimulus
    ) async throws -> Reading {
        try skipUnlessExperimentRequested()
        let fileManager = FileManager.default
        let extensionURL = fileManager.temporaryDirectory.appending(
            path: "crest-wake-probe-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try writeFixture(at: extensionURL)
        defer { try? fileManager.removeItem(at: extensionURL) }

        let profile = BrowsingProfile()
        let tab = BrowserTab(
            title: "Wake probe",
            url: URL(string: "https://example.com/"),
            placement: .current
        )
        let space = BrowserSpace(
            id: SpaceID(),
            profile: profile,
            name: "Wake probe",
            symbol: "puzzlepiece.extension.fill",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [space],
                selectedSpaceID: space.id
            ),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let pool = BrowserExtensionControllerPool(
            usesEphemeralWebKitStorage: Self.usesEphemeralStorage
        )
        // A real page on the same controller, on screen, so the session under
        // measurement has the shape a person's does rather than being an
        // extension alone in an empty app.
        let pageProvider = PageProviderSpy()
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 900, height: 700),
            configuration: BrowserPageConfiguration.make(
                for: profile,
                webExtensionController: pool.controller(for: space)
            )
        )
        pageProvider.webViews[tab.id] = webView
        pool.connect(browser: browser, pageProvider: pageProvider)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        await load(try XCTUnwrap(tab.url), in: webView)

        // The grant has to be in the snapshot the context is loaded with. A
        // grant applied afterwards arrives behind the background's first run,
        // so the first thing the fixture records would be lost.
        let snapshot = BrowserExtensionPermissionSnapshot(
            grantedPermissions: [
                "tabs": .distantFuture,
                "storage": .distantFuture,
            ],
            grantedHosts: ["*://*/*": .distantFuture]
        )
        mark(label, "loading")
        let context = try await pool.loadExtension(
            at: extensionURL,
            extensionID: "wake-probe",
            in: space,
            permissionSnapshot: snapshot
        )
        let loadedAt = Date()
        mark(label, "loaded")

        try await Task.sleep(for: idle)
        let dispatchedAt = Date()
        mark(label, "dispatching \(stimulus.rawValue)")
        switch stimulus {
        case .none:
            break
        case .changedProperties:
            let controller = pool.controller(for: space)
            let adapter = try XCTUnwrap(
                pool.extensionTab(tab.id, in: space.id)
            )
            controller.didChangeTabProperties([.URL, .title], for: adapter)
        case .openedTab:
            _ = browser.openNewTab(
                url: try XCTUnwrap(URL(string: "https://example.org/")),
                in: space.id
            )
            pool.reconcileExtensionState(in: browser.session)
        }
        mark(label, "dispatched \(stimulus.rawValue)")

        // Long enough for a restarted worker to evaluate, register, run its
        // listener, and land a write.
        try await Task.sleep(for: .seconds(5))
        let readAt = Date()
        mark(label, "reading")
        let store = await readStore(from: context)
        mark(label, "read \(store)")

        let report = """
            === wake experiment: \(label) ===
            ephemeral storage: \(Self.usesEphemeralStorage)
            loaded at:      \(Self.stamp(loadedAt))
            dispatched at:  \(Self.stamp(dispatchedAt)) (\(stimulus.rawValue))
            read at:        \(Self.stamp(readAt))
            extension store: \(store)
            context errors: \(context.errors.map(\.localizedDescription))
            """
        print(report)

        // A persistent run writes a real WebKit store into the app container.
        // It is keyed by this profile's fresh identifier, so it belongs to
        // nobody, but it still has to be taken away again afterwards.
        if !Self.usesEphemeralStorage {
            _ = try? await pool.deleteData(for: space)
            try? await WKWebsiteDataStore.remove(forIdentifier: profile.id)
        }
        return Reading(
            store: store,
            dispatchedAt: dispatchedAt.timeIntervalSince1970 * 1000
        )
    }

    private func load(_ url: URL, in webView: WKWebView) async {
        webView.load(URLRequest(url: url))
        for _ in 0..<200 {
            try? await Task.sleep(for: .milliseconds(50))
            if !webView.isLoading { break }
        }
    }

    /// Reads the fixture's own record out of `chrome.storage.local`.
    ///
    /// The popup reads storage directly rather than messaging the background,
    /// so the readback cannot itself be the thing that woke the worker.
    private func readStore(
        from context: WKWebExtensionContext
    ) async -> String {
        guard let action = context.action(for: nil) else {
            return "no action"
        }
        _ = action.popupPopover
        for _ in 0..<400 {
            if let popupWebView = action.popupWebView,
                let text = try? await popupWebView.evaluateJavaScript(
                    "document.body.innerText"
                ) as? String,
                text.hasPrefix("{")
            {
                return text
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return "never reported"
    }

    private func writeFixture(at extensionURL: URL) throws {
        try FileManager.default.createDirectory(
            at: extensionURL,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Wake Probe",
            "description": "Records when its worker runs and what reaches it.",
            "version": "1.0",
            "permissions": ["tabs", "storage"],
            "host_permissions": ["*://*/*"],
            "background": ["service_worker": "background.js"],
            "action": ["default_popup": "popup.html"],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: extensionURL.appending(path: "manifest.json")
        )
        try Data(Self.backgroundScript.utf8).write(
            to: extensionURL.appending(path: "background.js")
        )
        try Data(
            """
            <!doctype html><title>Wake probe</title>
            <body>reading</body><script src="popup.js"></script>
            """.utf8
        ).write(to: extensionURL.appending(path: "popup.html"))
        try Data(
            """
            // Reads storage directly. Messaging the background would be the
            // one thing guaranteed to wake it, which is what this measures.
            const render = () =>
                chrome.storage.local.get(null, (stored) => {
                    document.body.textContent = JSON.stringify(stored ?? {});
                });
            render();
            setInterval(render, 250);
            """.utf8
        ).write(to: extensionURL.appending(path: "popup.js"))
    }

    /// Listeners are registered synchronously at the top level, which is what
    /// MV3 requires for a stopped worker to be restarted for them at all. The
    /// start record is appended afterwards so it can never displace them.
    private static let backgroundScript = """
        // Appends are serialized. Two `chrome.storage.local.set` calls in
        // flight at once lose one of their keys.
        let queue = Promise.resolve();
        const append = (key, value) => {
            queue = queue.then(async () => {
                const stored = await chrome.storage.local.get({[key]: []});
                const list = stored[key] ?? [];
                list.push(value);
                await chrome.storage.local.set({[key]: list});
            });
            return queue;
        };
        chrome.runtime.onInstalled.addListener((details) => {
            append("installs", details.reason + "@" + Date.now());
        });
        chrome.tabs.onCreated.addListener(() => {
            append("created", Date.now());
        });
        chrome.tabs.onUpdated.addListener((tabID, changeInfo) => {
            append(
                "updated",
                Object.keys(changeInfo ?? {}).join("|") + "@" + Date.now()
            );
        });
        chrome.runtime.onMessage.addListener((message, sender, reply) => {
            chrome.storage.local.get(null, reply);
            return true;
        });
        append("starts", Date.now());
        """

    private static var usesEphemeralStorage: Bool {
        !isRequested(
            variable: "CREST_WAKE_PERSISTENT_STORE",
            marker: "/tmp/CrestWakePersistentStore"
        )
    }

    private static func isRequested(variable: String, marker: String) -> Bool {
        ProcessInfo.processInfo.environment[variable] == "1"
            || FileManager.default.fileExists(atPath: marker)
    }

    private static func stamp(_ date: Date) -> String {
        "\(date.timeIntervalSince1970 * 1000) (\(date))"
    }

    private func mark(_ label: String, _ note: String) {
        Self.log.notice(
            "CrestWakeProbe \(label, privacy: .public) \(note, privacy: .public)"
        )
    }

    private func skipUnlessExperimentRequested() throws {
        guard
            Self.isRequested(
                variable: "CREST_RUN_BACKGROUND_WAKE_EXPERIMENT",
                marker: "/tmp/CrestRunBackgroundWakeExperiment"
            )
        else {
            throw XCTSkip(
                """
                Set CREST_RUN_BACKGROUND_WAKE_EXPERIMENT=1 to measure whether a \
                tab event restarts a reaped background service worker.
                """
            )
        }
    }
}
