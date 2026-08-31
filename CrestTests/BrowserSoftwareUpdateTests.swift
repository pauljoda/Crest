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
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool,
            true
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUScheduledCheckInterval")
                as? Double,
            BrowserSoftwareUpdateRefreshCoordinator.minimumAutomaticCheckInterval
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUAutomaticallyUpdate") as? Bool,
            true
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "CrestDefaultUpdateChannel") as? String,
            "stable"
        )
    }

    func testReleaseChannelsMapToTheirSignedFeedsAndSparkleChannels() {
        XCTAssertEqual(BrowserSoftwareUpdateChannel.stable.allowedSparkleChannels, [])
        XCTAssertNil(BrowserSoftwareUpdateChannel.stable.customFeedURL)
        XCTAssertEqual(
            BrowserSoftwareUpdateChannel.nightly.allowedSparkleChannels,
            ["nightly"]
        )
        XCTAssertNil(BrowserSoftwareUpdateChannel.nightly.customFeedURL)
        XCTAssertEqual(
            BrowserSoftwareUpdateChannel.development.allowedSparkleChannels,
            ["development"]
        )
        XCTAssertEqual(
            BrowserSoftwareUpdateChannel.development.customFeedURL?.absoluteString,
            "https://raw.githubusercontent.com/pauljoda/Crest/updates/appcast-development.xml"
        )
    }

    func testBundledChannelBecomesTheDefaultUntilTheUserChoosesAnother() {
        let suiteName = "BrowserSoftwareUpdateTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }

        let service = BrowserSoftwareUpdateService(
            isEnabled: false,
            preferences: preferences,
            defaultChannel: .development
        )

        XCTAssertEqual(service.channel, .development)

        service.channel = .nightly

        XCTAssertEqual(
            preferences.string(
                forKey: BrowserSoftwareUpdateService.channelPreferenceKey
            ),
            BrowserSoftwareUpdateChannel.nightly.rawValue
        )
    }

    func testInstallingAnArtifactFromAnotherChannelAdoptsItsBundledChannel() {
        let suiteName = "BrowserSoftwareUpdateTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        preferences.set(
            BrowserSoftwareUpdateChannel.stable.rawValue,
            forKey: BrowserSoftwareUpdateService.channelPreferenceKey
        )
        preferences.set(
            BrowserSoftwareUpdateChannel.stable.rawValue,
            forKey: BrowserSoftwareUpdateService.bundledChannelPreferenceKey
        )

        let service = BrowserSoftwareUpdateService(
            isEnabled: false,
            preferences: preferences,
            defaultChannel: .development
        )

        XCTAssertEqual(service.channel, .development)
        XCTAssertEqual(
            preferences.string(
                forKey: BrowserSoftwareUpdateService.channelPreferenceKey
            ),
            BrowserSoftwareUpdateChannel.development.rawValue
        )
    }

    func testUserChoiceSurvivesRelaunchesOfTheSameArtifactChannel() {
        let suiteName = "BrowserSoftwareUpdateTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        preferences.set(
            BrowserSoftwareUpdateChannel.nightly.rawValue,
            forKey: BrowserSoftwareUpdateService.channelPreferenceKey
        )
        preferences.set(
            BrowserSoftwareUpdateChannel.development.rawValue,
            forKey: BrowserSoftwareUpdateService.bundledChannelPreferenceKey
        )

        let service = BrowserSoftwareUpdateService(
            isEnabled: false,
            preferences: preferences,
            defaultChannel: .development
        )

        XCTAssertEqual(service.channel, .nightly)
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
            skip: {}
        )

        model.installUpdate()
        model.installUpdate()

        XCTAssertEqual(installationCount, 1)
        XCTAssertEqual(model.phase, .downloading)
    }

    func testDeferringAManuallyFoundUpdateKeepsItsWidgetActionable() async throws {
        let source = BrowserSoftwareUpdateWidgetSource()
        let model = BrowserSoftwareUpdateModel(widgetSource: source)
        var iterator = source.events().makeAsyncIterator()
        _ = await iterator.next()
        var installationCount = 0
        var skipCount = 0

        model.presentUpdate(
            title: "Crest 1.0",
            version: "1.0.0",
            build: "100",
            isInformationOnly: false,
            install: { installationCount += 1 },
            skip: { skipCount += 1 }
        )
        let availableEmission = await iterator.next()
        let available = try XCTUnwrap(availableEmission?.first)
        XCTAssertEqual(model.presentationRevision, 1)

        model.deferUpdatePresentation()
        model.deferUpdatePresentation()

        XCTAssertEqual(model.phase, .updateAvailable)
        XCTAssertEqual(model.dismissalRevision, 1)
        XCTAssertNotNil(model.sidebarWidgetSnapshot)
        XCTAssertEqual(installationCount, 0)
        XCTAssertEqual(skipCount, 0)

        source.perform(.installUpdate, on: available.id)

        XCTAssertEqual(installationCount, 1)
        XCTAssertEqual(skipCount, 0)
        XCTAssertEqual(model.phase, .downloading)
        let downloadingEmission = await iterator.next()
        guard
            case .softwareUpdate(let snapshot) = try XCTUnwrap(
                downloadingEmission?.first
            ).presentation
        else { return XCTFail("Expected a software-update presentation") }
        XCTAssertEqual(snapshot.phase, .downloading)
    }

    func testBackgroundDiscoveryPublishesWidgetWithoutOpeningWindow() async throws {
        let source = BrowserSoftwareUpdateWidgetSource()
        let model = BrowserSoftwareUpdateModel(widgetSource: source)
        var iterator = source.events().makeAsyncIterator()
        _ = await iterator.next()

        model.presentUpdate(
            title: "Crest 1.0",
            version: "1.0.0",
            build: "100",
            isInformationOnly: false,
            suppressesWindowPresentation: true,
            install: {},
            skip: {}
        )

        let backgroundEmission = await iterator.next()
        XCTAssertNotNil(backgroundEmission?.first)
        XCTAssertEqual(model.presentationRevision, 0)
        XCTAssertEqual(model.dismissalRevision, 0)

        model.focus()

        XCTAssertEqual(model.presentationRevision, 1)
    }

    func testAutomaticDownloadOwnsWidgetThroughRestartReadiness() async throws {
        let source = BrowserSoftwareUpdateWidgetSource()
        let model = BrowserSoftwareUpdateModel(widgetSource: source)
        let presenter = BrowserAutomaticSoftwareUpdatePresenter(model: model)
        let update = BrowserSoftwareUpdateMetadata(
            title: "Crest 1.0",
            version: "1.0.0",
            build: "100",
            releaseNotes: "Automatic update notes",
            informationURL: nil
        )
        var iterator = source.events().makeAsyncIterator()
        _ = await iterator.next()
        var relaunchCount = 0

        presenter.downloadDidBegin(update)

        let downloadingEmission = await iterator.next()
        let downloading = try XCTUnwrap(downloadingEmission?.first)
        guard case .softwareUpdate(let download) = downloading.presentation else {
            return XCTFail("Expected an automatic download widget")
        }
        XCTAssertEqual(download.phase, .downloading)
        XCTAssertEqual(download.build, "100")
        XCTAssertEqual(downloading.availableActions, [])
        XCTAssertTrue(model.isAutomaticUpdate)
        XCTAssertEqual(model.presentationRevision, 0)

        presenter.extractionDidBegin(update)

        let extractingEmission = await iterator.next()
        let extracting = try XCTUnwrap(extractingEmission?.first)
        guard case .softwareUpdate(let extraction) = extracting.presentation else {
            return XCTFail("Expected an automatic extraction widget")
        }
        XCTAssertEqual(extraction.phase, .extracting)
        XCTAssertEqual(extracting.availableActions, [])

        presenter.installationDidBecomeReady(
            update,
            installAndRelaunch: { relaunchCount += 1 }
        )

        let readyEmission = await iterator.next()
        let ready = try XCTUnwrap(readyEmission?.first)
        guard case .softwareUpdate(let prepared) = ready.presentation else {
            return XCTFail("Expected an automatic restart widget")
        }
        XCTAssertEqual(prepared.phase, .readyToInstall)
        XCTAssertEqual(ready.availableActions, [.installAndRelaunch])

        source.perform(.installAndRelaunch, on: ready.id)

        XCTAssertEqual(relaunchCount, 1)
        XCTAssertEqual(model.phase, .installing)
    }

    func testManualUpdateWidgetOffersDownloadAndExplicitVersionSkip() async throws {
        let source = BrowserSoftwareUpdateWidgetSource()
        let model = BrowserSoftwareUpdateModel(widgetSource: source)
        let presenter = BrowserAutomaticSoftwareUpdatePresenter(model: model)
        let update = BrowserSoftwareUpdateMetadata(
            title: "Crest 1.0",
            version: "1.0.0",
            build: "100",
            releaseNotes: nil,
            informationURL: nil
        )
        var iterator = source.events().makeAsyncIterator()
        _ = await iterator.next()

        model.presentUpdate(
            title: update.title,
            version: update.version,
            build: update.build,
            isInformationOnly: false,
            install: {},
            skip: {}
        )

        let availableEmission = await iterator.next()
        let available = try XCTUnwrap(availableEmission?.first)
        XCTAssertEqual(
            available.availableActions,
            [.installUpdate, .dismissExactUpdate]
        )
        XCTAssertFalse(model.isAutomaticUpdate)

        source.perform(.installUpdate, on: available.id)
        _ = await iterator.next()
        presenter.downloadDidBegin(update)

        XCTAssertFalse(model.isAutomaticUpdate)
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

    func testSidebarWidgetDismissesTheExactBuildAndAChangedBuildReappears() async throws {
        let source = BrowserSoftwareUpdateWidgetSource()
        let model = BrowserSoftwareUpdateModel(widgetSource: source)
        var iterator = source.events().makeAsyncIterator()
        let initial = await iterator.next()
        XCTAssertEqual(initial, [])
        var skippedBuilds: [String] = []

        model.presentUpdate(
            title: "Crest 0.5.1",
            version: "0.5.1",
            build: "501",
            isInformationOnly: false,
            install: {},
            skip: { skippedBuilds.append("501") }
        )
        let firstEmission = await iterator.next()
        let first = try XCTUnwrap(firstEmission?.first)
        XCTAssertEqual(first.id.instanceID, "501")

        source.perform(.dismissExactUpdate, on: first.id)
        XCTAssertEqual(skippedBuilds, ["501"])
        let dismissed = await iterator.next()
        XCTAssertEqual(dismissed, [])

        model.presentUpdate(
            title: "Crest 0.5.2",
            version: "0.5.2",
            build: "502",
            isInformationOnly: false,
            install: {},
            skip: { skippedBuilds.append("502") }
        )
        let newerEmission = await iterator.next()
        let newer = try XCTUnwrap(newerEmission?.first)
        XCTAssertEqual(newer.id.instanceID, "502")
        XCTAssertNotEqual(newer.id, first.id)
    }

    func testIsolatedSidebarFixtureDoesNotPresentTheUpdaterWindow() async throws {
        let service = BrowserSoftwareUpdateService(
            isEnabled: false,
            preferences: nil
        )
        var iterator = service.widgetSource.events().makeAsyncIterator()
        _ = await iterator.next()
        let initialPresentationRevision = service.model.presentationRevision

        service.presentIsolatedSidebarWidgetFixture("available:0.5.99:599")

        let emission = await iterator.next()
        let instance = try XCTUnwrap(emission?.first)
        XCTAssertEqual(instance.id.instanceID, "599")
        XCTAssertEqual(
            service.model.presentationRevision,
            initialPresentationRevision
        )
    }

    func testSidebarWidgetRoutesInstallProgressReadyAndErrorActions() async throws {
        let source = BrowserSoftwareUpdateWidgetSource()
        let model = BrowserSoftwareUpdateModel(widgetSource: source)
        var iterator = source.events().makeAsyncIterator()
        _ = await iterator.next()
        var installCount = 0
        var relaunchCount = 0
        var acknowledgementCount = 0

        model.presentUpdate(
            title: "Crest 0.5.1",
            version: "0.5.1",
            build: "501",
            isInformationOnly: false,
            install: { installCount += 1 },
            skip: {}
        )
        let availableEmission = await iterator.next()
        let available = try XCTUnwrap(availableEmission?.first)
        source.perform(.installUpdate, on: available.id)
        XCTAssertEqual(installCount, 1)
        let beginningDownloadEmission = await iterator.next()
        let beginningDownload = try XCTUnwrap(beginningDownloadEmission?.first)
        guard case .softwareUpdate(let download) = beginningDownload.presentation
        else { return XCTFail("Expected a software-update presentation") }
        XCTAssertEqual(download.phase, .downloading)

        model.presentDownload(cancellation: {})
        _ = await iterator.next()
        model.setExpectedDownloadLength(100)
        model.receiveDownloadedBytes(40)
        let progressingEmission = await iterator.next()
        let progressing = try XCTUnwrap(progressingEmission?.first)
        guard case .softwareUpdate(let progress) = progressing.presentation
        else { return XCTFail("Expected download progress") }
        XCTAssertEqual(try XCTUnwrap(progress.progress), 0.4, accuracy: 0.001)

        model.presentReadyToInstall(
            install: { relaunchCount += 1 },
            cancel: {}
        )
        let readyEmission = await iterator.next()
        let ready = try XCTUnwrap(readyEmission?.first)
        source.perform(.installAndRelaunch, on: ready.id)
        XCTAssertEqual(relaunchCount, 1)

        model.presentError(
            message: "Fixture updater failed safely.",
            acknowledgement: { acknowledgementCount += 1 }
        )
        let failedEmission = await iterator.next()
        let failed = try XCTUnwrap(failedEmission?.first)
        source.perform(.acknowledgeError, on: failed.id)
        XCTAssertEqual(acknowledgementCount, 1)
        let acknowledged = await iterator.next()
        XCTAssertEqual(acknowledged, [])
    }

    func testReleaseNotesPreserveMarkdownBlockHierarchy() {
        let document = BrowserSoftwareUpdateReleaseNotesDocument(
            markdown: """
                ## Highlights

                A short introduction with **emphasis**.

                ### Fixed

                - Restored tab selection
                - Kept extension pages live

                [View all changes](https://example.com/compare)
                """
        )

        XCTAssertEqual(
            document.blocks.map(\.kind),
            [
                .heading(level: 2),
                .paragraph,
                .heading(level: 3),
                .bullet,
                .bullet,
                .paragraph,
            ]
        )
        XCTAssertEqual(
            document.blocks.map(\.plainText),
            [
                "Highlights",
                "A short introduction with emphasis.",
                "Fixed",
                "Restored tab selection",
                "Kept extension pages live",
                "View all changes",
            ]
        )
    }

    func testReleaseNotesKeepWrappedParagraphsTogether() {
        let document = BrowserSoftwareUpdateReleaseNotesDocument(
            markdown: """
                Development builds contain the newest changes and may be less
                reliable than stable releases.
                - Includes the latest browsing improvements.

                ---
                """
        )

        XCTAssertEqual(
            document.blocks.map(\.kind),
            [.paragraph, .bullet, .divider]
        )
        XCTAssertEqual(
            document.blocks.first?.plainText,
            "Development builds contain the newest changes and may be less reliable than stable releases."
        )
        XCTAssertEqual(
            document.blocks.dropFirst().first?.plainText,
            "Includes the latest browsing improvements."
        )
    }
}
