import XCTest

@testable import Crest

@MainActor
final class BrowserSoftwareUpdateTests: XCTestCase {
    func testApplicationRequiresSignedSparkleUpdatesFromTheOfficialFeed() throws {
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            "https://raw.githubusercontent.com/pauljoda/Crest/updates/appcast.xml"
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            "x/dBoNAjtYIa+JKUUHY48NYepidnElHTo3w2VMyqzLA="
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SURequireSignedFeed") as? Bool,
            true
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUVerifyUpdateBeforeExtraction") as? Bool,
            true
        )
    }

    func testStableAndNightlyChannelsMapToSparkleWithoutExcludingStableUpdates() {
        XCTAssertEqual(BrowserSoftwareUpdateChannel.stable.allowedSparkleChannels, [])
        XCTAssertEqual(
            BrowserSoftwareUpdateChannel.nightly.allowedSparkleChannels,
            ["nightly"]
        )
    }

    func testDownloadProgressAccumulatesAndClampsToTheExpectedLength() throws {
        let model = BrowserSoftwareUpdateModel()

        model.presentDownload(cancellation: {})
        model.setExpectedDownloadLength(100)
        model.receiveDownloadedBytes(30)
        XCTAssertEqual(try XCTUnwrap(model.progress), 0.3, accuracy: 0.001)

        model.receiveDownloadedBytes(90)
        XCTAssertEqual(try XCTUnwrap(model.progress), 1, accuracy: 0.001)
    }

    func testUpdateChoiceIsForwardedOnceAndClosesThePresentation() {
        let model = BrowserSoftwareUpdateModel()
        var installationCount = 0

        model.presentUpdate(
            title: "Crest 1.0",
            version: "1.0.0",
            isInformationOnly: false,
            install: { installationCount += 1 },
            dismiss: {},
            skip: {}
        )

        model.installUpdate()
        model.installUpdate()

        XCTAssertEqual(installationCount, 1)
        XCTAssertEqual(model.phase, .downloading)
    }

    func testInstallationRetryIsOnlyAvailableWhileCrestIsStillRunning() {
        let model = BrowserSoftwareUpdateModel()
        var retryCount = 0

        model.presentInstalling(
            applicationTerminated: false,
            retryTermination: { retryCount += 1 }
        )
        XCTAssertTrue(model.canRetryTermination)

        model.retryApplicationTermination()
        XCTAssertEqual(retryCount, 1)

        model.presentInstalling(
            applicationTerminated: true,
            retryTermination: { retryCount += 1 }
        )
        XCTAssertFalse(model.canRetryTermination)

        model.retryApplicationTermination()
        XCTAssertEqual(retryCount, 1)
    }
}
