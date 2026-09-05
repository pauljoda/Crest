import Foundation
import WebKit

@MainActor
final class BrowserChromeDebuggerDOMSnapshot {
    private let connection: BrowserWebInspectorProtocolConnection
    private let dom: BrowserChromeDebuggerDOM
    private weak var webView: WKWebView?
    private static let worldName = "Crest Debugger DOM Snapshot"
    private static var sharedWorld: WKContentWorld?

    init(connection: BrowserWebInspectorProtocolConnection, dom: BrowserChromeDebuggerDOM, webView: WKWebView) {
        self.connection = connection
        self.dom = dom
        self.webView = webView
    }

    func capture(_ parameters: [String: Any]) async throws -> [String: Any] {
        try Task.checkCancellation()
        try dom.activate()
        try connection.authorizeCommand?()
        guard let webView else { throw BrowserWebInspectorProtocolError.notConnected }
        guard let styles = parameters["computedStyles"] as? [String] else {
            throw BrowserChromeDebuggerProtocolError.invalidParameter("computedStyles")
        }
        for name in [
            "includePaintOrder", "includeDOMRects", "includeBlendedBackgroundColors", "includeTextColorOpacities",
        ] {
            if try BrowserChromeDebuggerValues.boolean(name, in: parameters) {
                throw BrowserChromeDebuggerProtocolError.unsupportedParameter(name)
            }
        }
        if Self.sharedWorld == nil {
            Self.sharedWorld = try BrowserChromeDebuggerSnapshotWorld.make(name: Self.worldName)
        }
        guard let world = Self.sharedWorld else { throw BrowserChromeDebuggerProtocolError.invalidResult }
        _ = try await dom.document()
        let generation = dom.generation
        let frames = try await BrowserChromeDebuggerSnapshotFrames.read(in: webView)
        var cleanups: [(WKFrameInfo, String)] = []
        do {
            var snapshots: [BrowserChromeDebuggerDocumentSnapshot] = []
            for frame in frames {
                try Task.checkCancellation()
                try connection.authorizeCommand?()
                let key = UUID().uuidString
                cleanups.append((frame, key))
                let raw = try await webView.callAsyncJavaScript(
                    BrowserChromeDebuggerDOMSnapshotScript.source,
                    arguments: [
                        "snapshotKey": key, "computedStyles": styles, "nodeRegistryKey": dom.snapshotRegistryKey,
                    ], in: frame, contentWorld: world)
                guard let result = raw as? [String: Any], let document = result["document"] as? [String: Any],
                    let strings = result["strings"] as? [String], let owners = result["childFrameOwners"] as? [Int],
                    let nodes = document["nodes"] as? [String: Any], let types = nodes["nodeType"] as? [Int],
                    let weakIDs = result["weakNodeIDs"] as? [Int], weakIDs.count == types.count
                else { throw BrowserChromeDebuggerProtocolError.invalidResult }
                let (objectID, frameID, contextID) = try await references(for: key)
                let nativeIDs = try await bindReferences(objectID, weakIDs: weakIDs)
                snapshots.append(
                    .init(
                        document: document, strings: strings, frameID: frameID,
                        nativeNodeIDs: nativeIDs, childFrameOwners: owners,
                        weakNodeIDs: weakIDs, contextID: contextID))
            }
            try validate(generation: generation)
            let result = try BrowserChromeDebuggerDOMSnapshotEncoding.encode(snapshots, dom: dom)
            await clean(cleanups, in: webView, world: world)
            try validate(generation: generation)
            return result
        } catch {
            await clean(cleanups, in: webView, world: world)
            throw error
        }
    }

    private func references(for key: String) async throws -> (String, String, Int) {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        repeat {
            try Task.checkCancellation()
            for context in try await connection.snapshotContexts(worldName: Self.worldName) {
                guard let id = context["id"] as? Int, let frameID = context["frameId"] as? String else {
                    throw BrowserChromeDebuggerProtocolError.invalidResult
                }
                // key is an application-generated UUID. No page text enters
                // this expression or can create a property in this world.
                let response = try await connection.sendCommand(
                    "Runtime.evaluate",
                    parameters: [
                        "expression": "globalThis.__crestDebuggerSnapshots?.get('\(key)')",
                        "contextId": id, "returnByValue": false, "objectGroup": key,
                        "doNotPauseOnExceptionsAndMuteConsole": true,
                    ])
                if let object = response["result"] as? [String: Any], let objectID = object["objectId"] as? String {
                    return (objectID, frameID, id)
                }
            }
            try await Task.sleep(for: .milliseconds(25))
        } while ContinuousClock.now < deadline
        throw BrowserChromeDebuggerProtocolError.invalidParameter("Snapshot frame context is unavailable")
    }

    private func bindReferences(_ objectID: String, weakIDs: [Int]) async throws -> [Int] {
        let expectedCount = weakIDs.count
        let response = try await connection.sendCommand(
            "Runtime.getProperties",
            parameters: [
                "objectId": objectID, "ownProperties": true, "generatePreview": false,
            ])
        guard let properties = response["properties"] as? [[String: Any]] else {
            throw BrowserChromeDebuggerProtocolError.invalidResult
        }
        var indexed: [Int: String] = [:]
        for property in properties {
            guard let name = property["name"] as? String, let index = Int(name), index >= 0,
                let value = property["value"] as? [String: Any], let id = value["objectId"] as? String
            else { continue }
            indexed[index] = id
        }
        guard indexed.count == expectedCount else { throw BrowserChromeDebuggerProtocolError.invalidResult }
        let objectIDs = try (0..<expectedCount).map { index in
            guard let id = indexed[index] else { throw BrowserChromeDebuggerProtocolError.invalidResult }
            return id
        }
        let nativeIndexes = objectIDs.indices.filter { weakIDs[$0] == 0 }
        let bound = try await connection.bindSnapshotNodes(objectIDs: nativeIndexes.map { objectIDs[$0] })
        var nativeIDs = Array(repeating: 0, count: expectedCount)
        for (index, id) in zip(nativeIndexes, bound) { nativeIDs[index] = id }
        return nativeIDs
    }

    private func validate(generation: Int) throws {
        try Task.checkCancellation()
        try connection.authorizeCommand?()
        guard connection.isConnected, dom.generation == generation else {
            throw BrowserChromeDebuggerProtocolError.invalidParameter("Document changed during snapshot")
        }
    }

    private func clean(_ entries: [(WKFrameInfo, String)], in webView: WKWebView, world: WKContentWorld) async {
        for (frame, key) in entries {
            _ = try? await webView.callAsyncJavaScript(
                "globalThis.__crestDebuggerSnapshots?.delete(snapshotKey);", arguments: ["snapshotKey": key],
                in: frame, contentWorld: world)
            _ = try? await connection.sendCommand("Runtime.releaseObjectGroup", parameters: ["objectGroup": key])
        }
    }
}
