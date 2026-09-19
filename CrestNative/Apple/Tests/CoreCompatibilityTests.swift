import Foundation
import XCTest
@testable import CrestControlPlane

@MainActor
final class CoreCompatibilityTests: XCTestCase {
    func testRejectedCommandDoesNotConsumeSequenceOrDiscardFollowingWork() async throws {
        let rejected = expectation(description: "Unregistered command rejected")
        let projected = expectation(description: "Following command reached core")
        let stopped = expectation(description: "Provider replies still drain shutdown")
        let windowID = UUID().uuidString.lowercased()
        var transport: CoreTransport?
        transport = try CoreTransport(adapters: [
            CoreAdapterDescriptor.make(id: "ui", role: "ui", implementation: "test.ui", supported: ["projections"]),
            CoreAdapterDescriptor.make(id: "engine", role: "engine", implementation: "test.engine", supported: ["pages", "navigation"]),
            CoreAdapterDescriptor.make(id: "platform", role: "platform", implementation: "test.platform", supported: ["surfaces"]),
        ], receive: { data in
            do {
                let message = try CoreMessage(data: data)
                if message.type == "ui.snapshot" {
                    let snapshot = try JSONDecoder().decode(CoreSnapshot.self,
                        from: JSONSerialization.data(withJSONObject: message.payload))
                    XCTAssertEqual(snapshot.windows.map(\.id), [windowID])
                    projected.fulfill()
                } else if message.type == "engine.dispose_all" {
                    transport?.post(type: "engine.stopped", payload: [:], sender: "engine", cause: message)
                } else if message.type == "core.operation_failed" { XCTFail("Following command failed") }
            } catch { XCTFail("Invalid output: \(error)") }
        }, failed: { failure in
            XCTAssertTrue(failure.contains("core.unregistered_test_command"))
            rejected.fulfill()
        }, stopped: { stopped.fulfill() })
        transport?.post(type: "core.unregistered_test_command", payload: [:])
        transport?.post(type: "core.open_window", payload: ["windowId": windowID])
        await fulfillment(of: [rejected, projected], timeout: 10)
        transport?.shutdown()
        await fulfillment(of: [stopped], timeout: 10)
    }
    func testLargeProjectionCommitsOnlyAfterValidatedNativeTransportFrames() async throws {
        let spaces = (1...4).map { number in
            var space = BrowserSession.makeBlankSpace(number: number)
            space.tabs = (0..<750).map { index in
                BrowserTab(title: String(repeating: "x", count: 512) + " \(index)",
                    url: URL(string: "https://example.com/\(number)/\(index)"), placement: .current)
            }
            space.selectedTabID = nil
            return space
        }
        let session = BrowserSession(spaces: spaces, selectedSpaceID: spaces[0].id)
        let state: [String: Any] = ["formatVersion": 1, "workspaceId": UUID().uuidString.lowercased(),
            "session": try JSONSerialization.jsonObject(with: JSONEncoder().encode(session)), "windows": []]
        let projected = expectation(description: "Complete projection received")
        let stopped = expectation(description: "Core stopped")
        var transfer: CoreChunkTransfer?
        var snapshot: CoreSnapshot?
        var transport: CoreTransport?
        transport = try CoreTransport(adapters: [
            CoreAdapterDescriptor.make(id: "ui", role: "ui", implementation: "test.ui", supported: ["projections"]),
            CoreAdapterDescriptor.make(id: "engine", role: "engine", implementation: "test.engine", supported: ["pages", "navigation"]),
            CoreAdapterDescriptor.make(id: "platform", role: "platform", implementation: "test.platform", supported: ["surfaces"]),
        ], initialState: state, receive: { data in
            do {
                XCTAssertLessThanOrEqual(data.count, 1_048_576)
                let message = try CoreMessage(data: data)
                switch message.type {
                case "ui.snapshot_begin":
                    XCTAssertNil(snapshot)
                    transfer = try CoreChunkTransfer(begin: message, identityKey: "snapshotId")
                case "ui.snapshot_chunk":
                    XCTAssertNil(snapshot)
                    try XCTUnwrap(transfer).append(message)
                case "ui.snapshot_commit":
                    snapshot = try JSONDecoder().decode(CoreSnapshot.self, from: XCTUnwrap(transfer).finish(message))
                    transfer = nil; projected.fulfill()
                case "engine.dispose_all":
                    transport?.post(type: "engine.stopped", payload: [:], sender: "engine", cause: message)
                case "core.operation_completed": break
                default: XCTFail("Unexpected output during dormant restoration: \(message.type)")
                }
            } catch { XCTFail("Projection transfer failed: \(error)") }
        }, failed: { XCTFail($0) }, stopped: { stopped.fulfill() })
        transport?.post(type: "core.snapshot", payload: [:])
        await fulfillment(of: [projected], timeout: 10)
        transport?.shutdown()
        await fulfillment(of: [stopped], timeout: 10)
        let result = try XCTUnwrap(snapshot)
        XCTAssertEqual(result.spaces.count, 4)
        XCTAssertEqual(result.spaces.flatMap(\.tabs).count, 3000)
        XCTAssertEqual(result.spaces.flatMap(\.tabs).map(\.id), spaces.flatMap(\.tabs).map { $0.id.rawValue.uuidString.lowercased() })
        XCTAssertTrue(result.spaces.flatMap(\.tabs).allSatisfy { $0.phase == "dormant" })
    }
    func testExistingSwiftSessionRoundTripsThroughNativeAOTWithoutLosingMetadata() async throws {
        try await roundTrip(large: false)
    }
    func testLargeSessionUsesBoundedChunksAndWritesAnAtomicCheckpoint() async throws {
        try await roundTrip(large: true)
    }
    private func roundTrip(large: Bool) async throws {
        var original = BrowserSession.freshInstallSeed
        let folder = BrowserFolder(title: "Reading", isCollapsed: true)
        let web = BrowserTab(
            title: "Observed title", url: URL(string: "https://example.com/article"),
            savedURL: URL(string: "https://example.com/"), symbol: "book.fill",
            faviconData: Data([1, 2, 3]), placement: .saved, folderID: folder.id,
            splitGroupID: SplitGroupID(), positionModifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            customTitle: "My reading", titleModifiedAt: Date(timeIntervalSince1970: 1_700_000_001),
            keepsPageLoaded: true)
        let settings = BrowserTab(title: "Settings", url: nil, nativeContent: .settings, placement: .current)
        original.spaces[0].folders = [folder]
        original.spaces[0].tabs = [web, settings]
        original.spaces[0].selectedTabID = web.id
        original.spaces[0].history = [
            BrowserHistoryEntry(
                url: web.url!, title: "Earlier title", firstVisitedAt: Date(timeIntervalSince1970: 1_700_000_000),
                lastVisitedAt: Date(timeIntervalSince1970: 1_700_000_002), visitCount: 4)
        ]
        original.spaces[0].archivedTabs = [
            ArchivedTab(
                tab: BrowserTab(title: "Closed", url: URL(string: "https://example.org"), placement: .current),
                archivedAt: Date(timeIntervalSince1970: 1_700_000_003), reason: .deletedOnAnotherDevice)
        ]
        var window = BrowserWindowState(restoring: original)
        window.captureSidebar(width: 271, isPresented: true)
        var state: [String: Any] = [
            "formatVersion": 1, "workspaceId": UUID().uuidString.lowercased(),
            "session": try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)),
            "windows": try JSONSerialization.jsonObject(with: JSONEncoder().encode([window])),
        ]
        if large { state["futureLargeProperty"] = String(repeating: "Unicode 🌊 ", count: 100_000) }
        let storageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("core-compatibility-\(UUID())")
        let storage = try CoreSessionStorage(directory: storageDirectory)
        defer { try? FileManager.default.removeItem(at: storageDirectory) }
        let saved = expectation(description: "Core emitted a migrated session")
        let stopped = expectation(description: "Native core drained and stopped")
        var savedState: [String: Any]?
        var transport: CoreTransport?
        transport = try CoreTransport(
            adapters: [
                CoreAdapterDescriptor.make(id: "ui", role: "ui", implementation: "test.ui", supported: ["projections"]),
                CoreAdapterDescriptor.make(id: "engine", role: "engine", implementation: "test.engine", supported: ["pages", "navigation"]),
                CoreAdapterDescriptor.make(id: "platform", role: "platform", implementation: "test.platform", supported: ["surfaces"]),
                CoreAdapterDescriptor.make(id: "services", role: "services", implementation: "test.storage", supported: ["session-storage"]),
            ], initialState: state, persistsSession: true,
            receive: { data in
                do {
                    let message = try CoreMessage(data: data)
                    if message.recipient == "services" {
                        storage.save(message) { request, success in
                            XCTAssertTrue(success)
                            do { savedState = try storage.load() } catch { XCTFail("Cannot reload saved checkpoint: \(error)") }
                            transport?.post(type: success ? "services.session_saved" : "services.save_failed",
                                payload: ["revision": request.payload["revision"]!], sender: "services", cause: request)
                            saved.fulfill()
                        }
                    } else if message.type == "engine.dispose_all" {
                        transport?.post(type: "engine.stopped", payload: [:], sender: "engine", cause: message)
                    } else if message.kind == "effect" {
                        XCTFail("Restoring dormant descriptors must not create native pages: \(message.type)")
                    } else if message.type == "core.operation_failed" {
                        XCTFail("Core rejected the compatibility fixture")
                    }
                } catch { XCTFail("Invalid core output: \(error)") }
            }, failed: { XCTFail($0) }, stopped: { stopped.fulfill() })
        transport?.post(type: "core.rename_space", payload: [
            "spaceId": original.spaces[0].id.rawValue.uuidString.lowercased(), "name": "Renamed in .NET",
        ])
        await fulfillment(of: [saved], timeout: 10)
        transport?.shutdown()
        await fulfillment(of: [stopped], timeout: 10)
        let output = try XCTUnwrap(savedState)
        if large { XCTAssertEqual(state["futureLargeProperty"] as? String, output["futureLargeProperty"] as? String) }
        let restored = try JSONDecoder().decode(BrowserSession.self, from: JSONSerialization.data(withJSONObject: output["session"]!))
        original.spaces[0].name = "Renamed in .NET"
        XCTAssertEqual(original, restored)
        let restoredWindows = try JSONDecoder().decode([BrowserWindowState].self, from: JSONSerialization.data(withJSONObject: output["windows"]!))
        XCTAssertEqual([window], restoredWindows)
    }
}
