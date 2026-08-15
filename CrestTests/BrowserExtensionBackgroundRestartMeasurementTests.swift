import AppKit
import OSLog
import WebKit
import XCTest

@testable import Crest

/// Measures what `unload` followed by `load` on the same extension context
/// looks like from inside the extension: whether it announces itself as a
/// fresh install, and whether the extension's stored data survives it.
///
/// This is the recovery Crest withdrew, kept as an instrument. A host that
/// wants to restart a wedged extension has only this lever, and the two
/// questions decide whether the lever is usable at all.
///
/// The reading is taken through `chrome.storage.local` rather than the
/// background's own memory, and through an extension page the run opens
/// itself rather than through the action popup, so nothing about the reading
/// depends on a popover being presentable from a test host.
@MainActor
final class BrowserExtensionBackgroundRestartMeasurementTests: XCTestCase {
    private static let log = Logger(
        subsystem: "com.pauldavis.crest.wake-experiment",
        category: "restart"
    )

    /// Runs against whichever store the marker selects. Production is
    /// persistent, and the ephemeral answer does not carry over to it: an
    /// ephemeral controller has nowhere to keep extension data across a
    /// context's lifetime in the first place.
    func testRestartingAnExtensionInPlaceIsMeasured() async throws {
        try skipUnlessExperimentRequested()
        let fileManager = FileManager.default
        let extensionURL = fileManager.temporaryDirectory.appending(
            path: "crest-restart-probe-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try writeFixture(at: extensionURL)
        defer { try? fileManager.removeItem(at: extensionURL) }

        let profile = BrowsingProfile()
        let space = BrowserSpace(
            id: SpaceID(),
            profile: profile,
            name: "Restart probe",
            symbol: "puzzlepiece.extension.fill",
            accent: .indigo,
            folders: [],
            tabs: [],
            selectedTabID: nil
        )
        let pool = BrowserExtensionControllerPool(
            usesEphemeralWebKitStorage: Self.usesEphemeralStorage
        )
        // Granted in the snapshot the context is loaded with. A grant applied
        // after the load arrives behind the background's first run, which is
        // what stopped an earlier attempt at this measurement from recording
        // anything about the first install.
        let snapshot = BrowserExtensionPermissionSnapshot(
            grantedPermissions: ["storage": .distantFuture]
        )
        Self.log.notice("CrestRestartProbe loading")
        let context = try await pool.loadExtension(
            at: extensionURL,
            extensionID: "restart-probe",
            in: space,
            permissionSnapshot: snapshot
        )
        let controller = pool.controller(for: space)

        // Past the fixture's own deferred start record, so a first reading is
        // taken against a background that has finished announcing itself.
        try await Task.sleep(for: .seconds(4))
        let onFirstLoad = try await store(in: context)
        try await write(
            "await chrome.storage.local.set({marker: 'set-before-restart'});",
            in: context
        )
        let beforeRestart = try await store(in: context)
        XCTAssertTrue(
            beforeRestart.contains("set-before-restart"),
            """
            Control failed: the marker was never stored (\(beforeRestart)), so \
            its absence after a restart would prove nothing about the restart.
            """
        )

        Self.log.notice("CrestRestartProbe restarting")
        try controller.unload(context)
        try controller.load(context)
        // Long enough for the background to come back up and for a late
        // `onInstalled` to be recorded before the reading is taken.
        try await Task.sleep(for: .seconds(5))
        let afterRestart = try await store(in: context)

        print(
            """
            === restart measurement ===
            ephemeral storage: \(Self.usesEphemeralStorage)
            on first load:  \(onFirstLoad)
            before restart: \(beforeRestart)
            after restart:  \(afterRestart)
            context errors: \(context.errors.map(\.localizedDescription))
            """
        )

        if !Self.usesEphemeralStorage {
            // The reading production depends on. A nonpersistent controller
            // keeps extension data only for the lifetime of the context, so
            // its own answer here says nothing about a shipping build.
            XCTAssertTrue(
                afterRestart.contains("set-before-restart"),
                """
                Restarting the extension destroyed its stored data \
                (\(afterRestart)). A recovery that clears `chrome.storage` \
                would be worse than the stranded popup it fixes.
                """
            )
            _ = try? await pool.deleteData(for: space)
            try? await WKWebsiteDataStore.remove(forIdentifier: profile.id)
        }
    }

    /// Opens one of the extension's own pages and reads its whole store.
    private func store(
        in context: WKWebExtensionContext
    ) async throws -> String {
        try await evaluate(
            "return JSON.stringify(await chrome.storage.local.get(null));",
            in: context
        ) ?? "unreadable"
    }

    private func write(
        _ body: String,
        in context: WKWebExtensionContext
    ) async throws {
        _ = try await evaluate(body + "\nreturn 'done';", in: context)
    }

    private func evaluate(
        _ body: String,
        in context: WKWebExtensionContext
    ) async throws -> String? {
        var page: WKWebView? = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 480),
            configuration: try XCTUnwrap(context.webViewConfiguration)
        )
        let url = context.baseURL.appending(path: "page.html")
        page?.load(URLRequest(url: url))
        for _ in 0..<200 {
            try await Task.sleep(for: .milliseconds(50))
            if page?.isLoading == false { break }
        }
        let value =
            try? await page?.callAsyncJavaScript(
                body,
                arguments: [:],
                in: nil,
                contentWorld: .page
            ) as? String
        page = nil
        return value ?? nil
    }

    private func writeFixture(at extensionURL: URL) throws {
        try FileManager.default.createDirectory(
            at: extensionURL,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Restart Probe",
            "description": "Records how it was started.",
            "version": "1.0",
            "permissions": ["storage"],
            "background": ["service_worker": "background.js"],
            "action": ["default_popup": "page.html"],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: extensionURL.appending(path: "manifest.json")
        )
        try Data(
            """
            // Appends are serialized. Two `chrome.storage.local.set` calls in
            // flight at once lose one of their keys, so an install recorded
            // beside a start disappears if they are allowed to overlap.
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
            // Every reason is appended, so a restart that announces an install
            // shows up beside the original rather than replacing it.
            chrome.runtime.onInstalled.addListener((details) => {
                // Both an unqueued flag and a queued append, so a missing
                // record can be read as "the event never arrived" rather than
                // as one write losing a race with another.
                chrome.storage.local.set({installedFlag: details.reason});
                append("installs", details.reason + "@" + Date.now());
            });
            // Held back so it cannot overlap an install arriving at startup.
            setTimeout(() => append("starts", Date.now()), 2000);
            """.utf8
        ).write(to: extensionURL.appending(path: "background.js"))
        try Data(
            """
            <!doctype html><title>Restart probe</title><body>ready</body>
            """.utf8
        ).write(to: extensionURL.appending(path: "page.html"))
    }

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

    private func skipUnlessExperimentRequested() throws {
        guard
            Self.isRequested(
                variable: "CREST_RUN_BACKGROUND_WAKE_EXPERIMENT",
                marker: "/tmp/CrestRunBackgroundWakeExperiment"
            )
        else {
            throw XCTSkip(
                """
                Set CREST_RUN_BACKGROUND_WAKE_EXPERIMENT=1 to measure what \
                restarting an extension context in place does to it.
                """
            )
        }
    }
}
