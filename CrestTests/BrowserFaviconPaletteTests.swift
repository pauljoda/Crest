import XCTest

@testable import Crest

final class BrowserFaviconPaletteTests: XCTestCase {
    func testPaletteChoosesTheContrastingCenterAccent() throws {
        let width = 16
        let height = 16
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = ((y * width) + x) * 4
                let isCenter = (4..<12).contains(x) && (4..<12).contains(y)
                pixels[offset] = isCenter ? 244 : 20
                pixels[offset + 1] = isCenter ? 62 : 86
                pixels[offset + 2] = isCenter ? 54 : 180
                pixels[offset + 3] = 255
            }
        }

        let palette = try XCTUnwrap(
            BrowserFaviconPaletteExtractor().palette(
                rgbaPixels: pixels,
                width: width,
                height: height
            )
        )

        XCTAssertGreaterThan(palette.primary.red, 0.75)
        XCTAssertLessThan(palette.primary.green, 0.4)
        XCTAssertLessThan(palette.primary.blue, 0.4)
    }

    func testConcurrentRequestsForTheSameDataShareOneInFlightExtraction() async {
        let provider = SuspendedFaviconPaletteProvider()
        let loader = BrowserFaviconPaletteLoader { data in
            await provider.palette(for: data)
        }
        let data = Data([0xCE, 0x57])

        let first = Task { await loader.palette(for: data) }
        await provider.waitUntilRequestStarts()
        let secondRequest = FaviconPaletteRequestStart()
        let second = Task {
            await secondRequest.recordStart()
            return await loader.palette(for: data)
        }
        await secondRequest.waitUntilStarted()
        await Task.yield()

        await provider.complete(with: nil)
        let firstPalette = await first.value
        let secondPalette = await second.value

        XCTAssertNil(firstPalette)
        XCTAssertNil(secondPalette)
        let requestCount = await provider.requestCount()
        XCTAssertEqual(requestCount, 1)
    }

    func testCacheKeeps128EntriesAndEvictsTheOldestInsertion() async {
        let provider = CountingFaviconPaletteProvider()
        let loader = BrowserFaviconPaletteLoader { data in
            await provider.palette(for: data)
        }
        let keys = (0...128).map(Self.cacheKey)

        for key in keys.prefix(128) {
            _ = await loader.palette(for: key)
        }
        _ = await loader.palette(for: keys[0])
        let cachedRequestCount = await provider.requestCount()
        XCTAssertEqual(cachedRequestCount, 128)

        _ = await loader.palette(for: keys[128])
        _ = await loader.palette(for: keys[1])
        let boundedRequestCount = await provider.requestCount()
        XCTAssertEqual(boundedRequestCount, 129)

        _ = await loader.palette(for: keys[0])
        let evictionRequestCount = await provider.requestCount()
        XCTAssertEqual(evictionRequestCount, 130)
    }

    private static func cacheKey(_ value: Int) -> Data {
        Data([UInt8(value >> 8), UInt8(value & 0xFF)])
    }
}

private actor SuspendedFaviconPaletteProvider {
    private var count = 0
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var continuation: CheckedContinuation<BrowserFaviconPalette?, Never>?

    func palette(for data: Data) async -> BrowserFaviconPalette? {
        count += 1
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        guard count == 1 else { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilRequestStarts() async {
        guard count == 0 else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func complete(with palette: BrowserFaviconPalette?) {
        continuation?.resume(returning: palette)
        continuation = nil
    }

    func requestCount() -> Int { count }
}

private actor CountingFaviconPaletteProvider {
    private var count = 0

    func palette(for data: Data) -> BrowserFaviconPalette? {
        count += 1
        return BrowserFaviconPalette(
            primary: BrowserFaviconColor(red: 0.7, green: 0.3, blue: 0.2)
        )
    }

    func requestCount() -> Int { count }
}

private actor FaviconPaletteRequestStart {
    private var hasStarted = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func recordStart() {
        hasStarted = true
        let waiters = waiters
        self.waiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitUntilStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
