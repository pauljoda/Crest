import Foundation
import XCTest

@testable import Crest

final class BrowserExtensionIconDecoderTests: XCTestCase {
    func testConcurrentWaitersShareWorkWhenTheCreatingWaiterIsCancelled() async {
        let port = SuspendedBrowserExtensionIconPort()
        let decoder = BrowserExtensionIconDecoder<Int>(decodingPort: port)
        let request = Self.request(data: Data([0xCE, 0x57]))

        let creatingWaiter = Task { await decoder.icon(for: request) }
        await port.waitUntilDecodingStarts()
        let joiningWaiter = Task { await decoder.icon(for: request) }
        for _ in 0..<20 {
            await Task.yield()
        }

        creatingWaiter.cancel()
        await port.complete(with: 42)

        let creatingResult = await creatingWaiter.value
        let joiningResult = await joiningWaiter.value
        let decodeCount = await port.decodeCount
        XCTAssertEqual(creatingResult, 42)
        XCTAssertEqual(joiningResult, 42)
        XCTAssertEqual(decodeCount, 1)
    }

    func testUnavailableDecoderResultIsNegativeCached() async {
        let encodedData = Self.encodedPNGData
        let port = UnavailableBrowserExtensionIconPort()
        let decoder = BrowserExtensionIconDecoder<Int>(decodingPort: port)
        let request = BrowserExtensionIconRequest(
            extensionID: "com.example.extension",
            spaceID: Self.spaceID(tail: 0x10),
            payload: BrowserExtensionIconPayloadFactory.production.payload(
                for: encodedData
            ),
            maximumPixelSize: 64
        )
        let first = await decoder.icon(for: request)
        let second = await decoder.icon(for: request)

        let decodeCount = await port.decodeCount
        let cachedEntryCount = await decoder.cachedEntryCount
        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(decodeCount, 1)
        XCTAssertEqual(cachedEntryCount, 1)
    }

    func testMalformedPayloadIsRejectedBeforeIdentificationOrDecoding() async {
        let identifierRecorder = BrowserExtensionIconIdentifierRecorder()
        let factory = BrowserExtensionIconPayloadFactory(
            testingValidate: { _ in false },
            testingIdentifier: { data in
                identifierRecorder.recordInvocation()
                return Self.identifier(
                    seed: UInt64(data.count),
                    byteCount: data.count
                )
            }
        )
        let malformedData = Data([0x00, 0x01, 0x02, 0x03])

        let payload = factory.payload(for: malformedData)
        let productionPayload = BrowserExtensionIconPayloadFactory.production
            .payload(for: malformedData)
        let port = CountingBrowserExtensionIconPort()
        let decoder = BrowserExtensionIconDecoder<Int>(decodingPort: port)
        let request = BrowserExtensionIconRequest(
            extensionID: "com.example.extension",
            spaceID: Self.spaceID(tail: 0x10),
            payload: payload,
            maximumPixelSize: 64
        )
        let result = await decoder.icon(for: request)

        let decodeCount = await port.decodeCount
        let cachedEntryCount = await decoder.cachedEntryCount
        let inFlightRequestCount = await decoder.inFlightRequestCount
        XCTAssertNil(payload)
        XCTAssertNil(productionPayload)
        XCTAssertNil(result)
        XCTAssertEqual(identifierRecorder.invocationCount, 0)
        XCTAssertEqual(decodeCount, 0)
        XCTAssertEqual(cachedEntryCount, 0)
        XCTAssertEqual(inFlightRequestCount, 0)
    }

    func testOversizedPayloadIsRejectedBeforeIdentificationDecodingOrCaching() async {
        let validationRecorder = BrowserExtensionIconIdentifierRecorder()
        let identifierRecorder = BrowserExtensionIconIdentifierRecorder()
        let factory = BrowserExtensionIconPayloadFactory(
            testingValidate: { _ in
                validationRecorder.recordInvocation()
                return true
            },
            testingIdentifier: { data in
                identifierRecorder.recordInvocation()
                return Self.identifier(
                    seed: UInt64(data.count),
                    byteCount: data.count
                )
            }
        )
        let oversizedData = Data(
            repeating: 0xCE,
            count: BrowserExtensionIconPayload.maximumEncodedByteCount + 1
        )

        let payload = factory.payload(for: oversizedData)
        let untrustedPayload = BrowserExtensionIconPayload(
            data: oversizedData,
            contentIdentifier: Self.identifier(
                seed: 1,
                byteCount: oversizedData.count
            )
        )
        let port = CountingBrowserExtensionIconPort()
        let decoder = BrowserExtensionIconDecoder<Int>(decodingPort: port)
        let request = BrowserExtensionIconRequest(
            extensionID: "com.example.extension",
            spaceID: Self.spaceID(tail: 0x10),
            payload: untrustedPayload,
            maximumPixelSize: 64
        )
        let result = await decoder.icon(for: request)

        let decodeCount = await port.decodeCount
        let cachedEntryCount = await decoder.cachedEntryCount
        let inFlightRequestCount = await decoder.inFlightRequestCount
        XCTAssertNil(payload)
        XCTAssertNil(result)
        XCTAssertEqual(validationRecorder.invocationCount, 0)
        XCTAssertEqual(identifierRecorder.invocationCount, 0)
        XCTAssertEqual(decodeCount, 0)
        XCTAssertEqual(cachedEntryCount, 0)
        XCTAssertEqual(inFlightRequestCount, 0)
    }

    func testCacheDoesNotShareDecodedArtworkAcrossSpaces() async {
        let port = CountingBrowserExtensionIconPort()
        let decoder = BrowserExtensionIconDecoder<Int>(decodingPort: port)
        let data = Data([0xCE, 0x57])
        let firstSpaceRequest = Self.request(
            extensionID: "com.example.extension",
            spaceID: Self.spaceID(tail: 0x10),
            data: data
        )
        let secondSpaceRequest = Self.request(
            extensionID: "com.example.extension",
            spaceID: Self.spaceID(tail: 0x20),
            data: data
        )

        _ = await decoder.icon(for: firstSpaceRequest)
        _ = await decoder.icon(for: secondSpaceRequest)
        _ = await decoder.icon(for: firstSpaceRequest)

        let decodeCount = await port.decodeCount
        XCTAssertEqual(decodeCount, 2)
    }

    private static func request(data: Data) -> BrowserExtensionIconRequest {
        request(
            extensionID: "com.example.extension",
            spaceID: spaceID(tail: 0x10),
            data: data
        )
    }

    private static func request(
        extensionID: String,
        spaceID: SpaceID,
        data: Data,
        maximumPixelSize: Int = 64
    ) -> BrowserExtensionIconRequest {
        BrowserExtensionIconRequest(
            extensionID: extensionID,
            spaceID: spaceID,
            payload: BrowserExtensionIconPayloadFactory(
                testingValidate: { _ in true },
                testingIdentifier: { data in
                    identifier(
                        seed: data.reduce(0xcbf2_9ce4_8422_2325) {
                            ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01b3
                        },
                        byteCount: data.count
                    )
                }
            ).payload(for: data),
            maximumPixelSize: maximumPixelSize
        )
    }

    private static func identifier(
        seed: UInt64,
        byteCount: Int
    ) -> BrowserExtensionIconContentIdentifier {
        BrowserExtensionIconContentIdentifier(
            encodedByteCount: byteCount,
            firstWord: seed,
            secondWord: seed &+ 1,
            thirdWord: seed &+ 2,
            fourthWord: seed &+ 3
        )
    }

    private static func spaceID(tail: UInt8) -> SpaceID {
        SpaceID(
            rawValue: UUID(
                uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, tail)
            )
        )
    }

    private static let encodedPNGData =
        Data(
            base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9WlO5h8AAAAASUVORK5CYII="
        ) ?? Data()
}

private actor SuspendedBrowserExtensionIconPort:
    BrowserExtensionIconDecoding
{
    private(set) var decodeCount = 0
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var completion: CheckedContinuation<Int?, Never>?

    func decode(_ data: Data, maximumPixelSize: Int) async -> Int? {
        decodeCount += 1
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        return await withCheckedContinuation { continuation in
            completion = continuation
        }
    }

    func waitUntilDecodingStarts() async {
        guard decodeCount == 0 else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func complete(with icon: Int?) {
        completion?.resume(returning: icon)
        completion = nil
    }
}

private actor CountingBrowserExtensionIconPort:
    BrowserExtensionIconDecoding
{
    private(set) var decodeCount = 0

    func decode(_ data: Data, maximumPixelSize: Int) -> Int? {
        decodeCount += 1
        return data.first.map(Int.init)
    }
}

private actor UnavailableBrowserExtensionIconPort:
    BrowserExtensionIconDecoding
{
    private(set) var decodeCount = 0

    func decode(_ data: Data, maximumPixelSize: Int) -> Int? {
        decodeCount += 1
        return nil
    }
}

private final class BrowserExtensionIconIdentifierRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var invocationCount: Int {
        lock.withLock { count }
    }

    func recordInvocation() {
        lock.withLock { count += 1 }
    }
}
