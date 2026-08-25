import ImageIO
@preconcurrency import MediaPlayer
import XCTest

@testable import Crest

@MainActor
final class BrowserSystemNowPlayingTests: XCTestCase {
    func testSystemArtworkCanBeRequestedFromMediaPlayerBackgroundQueue() async throws {
        let data = try makeArtworkData(width: 128, height: 128)

        let renderedSize = await Task.detached {
            BrowserMediaPlayerNowPlayingDriver.artwork(from: data)?
                .image(at: CGSize(width: 64, height: 64))?
                .size
        }.value

        XCTAssertEqual(renderedSize?.width, 64)
        XCTAssertEqual(renderedSize?.height, 64)
    }

    func testSystemArtworkPreservesWideAndTallSourceAspectRatios() throws {
        let wide = try BrowserMediaPlayerNowPlayingDriver.artwork(
            from: makeArtworkData(width: 240, height: 120)
        )?.image(at: CGSize(width: 64, height: 64))
        let tall = try BrowserMediaPlayerNowPlayingDriver.artwork(
            from: makeArtworkData(width: 120, height: 240)
        )?.image(at: CGSize(width: 64, height: 64))

        XCTAssertEqual(wide?.size.width, 64)
        XCTAssertEqual(wide?.size.height, 32)
        XCTAssertEqual(tall?.size.width, 32)
        XCTAssertEqual(tall?.size.height, 64)
    }

    private func makeArtworkData(width: Int, height: Int) throws -> Data {
        let bytes = Data(repeating: 0x7f, count: width * height * 4)
        let provider = try XCTUnwrap(CGDataProvider(data: bytes as CFData))
        let image = try XCTUnwrap(
            CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )
        )
        let output = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(
                output,
                "public.png" as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    func testSelectionPrefersPlayingThenAudibleThenNewest() {
        let paused = snapshot(
            title: "Paused",
            playback: .paused,
            audible: false,
            ordinal: 4
        )
        let quietPlaying = snapshot(
            title: "Quiet",
            playback: .playing,
            audible: false,
            ordinal: 5
        )
        let audiblePlaying = snapshot(
            title: "Audible",
            playback: .playing,
            audible: true,
            ordinal: 2
        )

        XCTAssertEqual(
            BrowserSystemNowPlayingSelectionPolicy.select(
                from: [paused, quietPlaying, audiblePlaying]
            ),
            audiblePlaying
        )
        XCTAssertNil(
            BrowserSystemNowPlayingSelectionPolicy.select(
                from: [
                    snapshot(
                        title: "Metadata only",
                        playback: .none,
                        audible: false,
                        ordinal: 1
                    )
                ]
            )
        )
    }

    func testCoordinatorPublishesStoreTruthRoutesCommandsAndClearsOnInvalidation() async throws {
        let store = BrowserMediaSessionStore()
        let endpoint = SystemNowPlayingFakeEndpoint()
        let driver = SystemNowPlayingFakeDriver()
        let coordinator = BrowserSystemNowPlayingCoordinator(
            store: store,
            driver: driver
        )
        let owner = BrowserTabRuntimeAssignment(
            tabID: TabID(),
            spaceID: SpaceID(),
            profileID: UUID()
        )
        let artwork = Data(repeating: 7, count: 32)
        coordinator.start()

        store.receive(
            BrowserMediaSessionPageEvent(
                documentIdentifier: "document",
                sequence: 1,
                location: "https://fixture.invalid/media",
                isInvalidated: false,
                hasActiveSession: true,
                title: "Track",
                artist: "Artist",
                album: "Album",
                artworkData: artwork,
                playbackState: .playing,
                isAudible: true,
                isMuted: false,
                availableActions: [.pause, .nextTrack]
            ),
            owner: owner,
            fallbackTitle: nil,
            endpoint: endpoint
        )
        try await waitUntil("the shared session to reach the system adapter") {
            driver.published.compactMap { $0 }.last?.title == "Track"
        }
        XCTAssertEqual(
            driver.published.compactMap { $0 }.last?.artworkData,
            artwork
        )
        XCTAssertTrue(driver.send(.pause))
        XCTAssertFalse(driver.send(.play))
        XCTAssertEqual(endpoint.actions, [.pause])

        store.invalidate(endpoint: endpoint)
        try await waitUntil("system Now Playing to clear after page invalidation") {
            driver.published.count >= 2 && driver.published.last! == nil
        }
        coordinator.stop()
        XCTAssertNil(driver.commandHandler)
    }

    private func snapshot(
        title: String,
        playback: BrowserMediaSessionPlaybackState,
        audible: Bool,
        ordinal: UInt64
    ) -> BrowserMediaSessionSnapshot {
        BrowserMediaSessionSnapshot(
            id: BrowserMediaSessionID(
                tabID: TabID(),
                documentIdentifier: UUID().uuidString
            ),
            owner: BrowserTabRuntimeAssignment(
                tabID: TabID(),
                spaceID: SpaceID(),
                profileID: UUID()
            ),
            ownerTitle: "Owner Tab",
            title: title,
            artist: nil,
            album: nil,
            artworkData: nil,
            playbackState: playback,
            isAudible: audible,
            isMuted: false,
            availableActions: [],
            orderingOrdinal: ordinal
        )
    }

    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(2),
        condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for \(description).")
    }
}

@MainActor
private final class SystemNowPlayingFakeDriver: BrowserSystemNowPlayingDriving {
    private(set) var commandHandler: ((BrowserMediaSessionAction) -> Bool)?
    private(set) var published: [BrowserMediaSessionSnapshot?] = []

    func setCommandHandler(
        _ handler: ((BrowserMediaSessionAction) -> Bool)?
    ) {
        commandHandler = handler
    }

    func publish(_ session: BrowserMediaSessionSnapshot?) {
        published.append(session)
    }

    func send(_ action: BrowserMediaSessionAction) -> Bool {
        commandHandler?(action) == true
    }
}

@MainActor
private final class SystemNowPlayingFakeEndpoint: BrowserMediaSessionCommandEndpoint {
    private(set) var actions: [BrowserMediaSessionAction] = []

    func performMediaSessionAction(
        _ action: BrowserMediaSessionAction,
        documentIdentifier: String
    ) {
        actions.append(action)
    }

    func setMediaSessionMuted(
        _ muted: Bool,
        documentIdentifier: String
    ) {}
}
