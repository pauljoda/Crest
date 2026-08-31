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

    func testEveryNonIdleUpdaterStateHasASidebarPresentation() {
        XCTAssertFalse(
            BrowserSceneID.allCases.map(\.rawValue).contains("software-update"),
            "Software updates must not own an auxiliary window scene."
        )

        let model = BrowserSoftwareUpdateModel()

        model.presentPermissionRequest(response: { _ in })
        XCTAssertEqual(model.sidebarWidgetSnapshot?.phase, .permission)

        model.presentChecking(cancellation: {})
        XCTAssertEqual(model.sidebarWidgetSnapshot?.phase, .checking)

        model.presentNoUpdate(message: "Crest is up to date.", acknowledgement: {})
        XCTAssertEqual(model.sidebarWidgetSnapshot?.phase, .upToDate)

        model.presentError(message: "The update check failed.", acknowledgement: {})
        XCTAssertEqual(model.sidebarWidgetSnapshot?.phase, .failed)

        model.presentInstalled(relaunched: true, acknowledgement: {})
        XCTAssertEqual(model.sidebarWidgetSnapshot?.phase, .installed)

        model.dismissInstallation()
        XCTAssertNil(model.sidebarWidgetSnapshot)
    }

    func testChangelogUsesAnExplicitDetailsSceneInsteadOfTheOldUpdateWindow() {
        let sceneIDs = Set(BrowserSceneID.allCases.map(\.rawValue))

        XCTAssertFalse(sceneIDs.contains("software-update"))
        XCTAssertTrue(
            sceneIDs.contains("software-update-details"),
            "The sidebar needs an explicit destination for reviewing update notes."
        )
        XCTAssertEqual(
            BrowserSceneID.softwareUpdateDetails.rawValue,
            BrowserSoftwareUpdateSceneID.details
        )
    }

    func testDownloadedReleaseNotesRefreshTheSidebarDetailsLink() async throws {
        let source = BrowserSoftwareUpdateWidgetSource()
        let model = BrowserSoftwareUpdateModel(widgetSource: source)
        var iterator = source.events().makeAsyncIterator()
        _ = await iterator.next()

        model.presentUpdate(
            title: "Crest 1.0",
            version: "1.0.0",
            build: "100",
            isInformationOnly: false,
            install: {},
            skip: {}
        )
        let initialEmission = await iterator.next()
        guard
            case .softwareUpdate(let initial) = try XCTUnwrap(
                initialEmission?.first
            ).presentation
        else { return XCTFail("Expected the update card") }
        XCTAssertNil(initial.releaseNotes)

        model.setReleaseNotes("## What's New\n\n- Sidebar updates")

        let refreshedEmission = await iterator.next()
        guard
            case .softwareUpdate(let refreshed) = try XCTUnwrap(
                refreshedEmission?.first
            ).presentation
        else { return XCTFail("Expected refreshed update details") }
        XCTAssertEqual(
            refreshed.releaseNotes,
            "## What's New\n\n- Sidebar updates"
        )
    }

    func testAutomaticUpdatePublishesThroughTheActiveSidebarRuntime() async throws {
        let source = BrowserSoftwareUpdateWidgetSource()
        let model = BrowserSoftwareUpdateModel(widgetSource: source)
        let presenter = BrowserAutomaticSoftwareUpdatePresenter(model: model)
        let runtime = BrowserSidebarWidgetRuntime(
            registrations: [.softwareUpdate],
            sources: [source]
        )
        runtime.activateHost(
            id: BrowserWindowID(),
            capabilities: [.persistentSidebar, .directSoftwareUpdates]
        )
        for _ in 0..<4 { await Task.yield() }

        let update = BrowserSoftwareUpdateMetadata(
            title: "Crest 1.0",
            version: "1.0.0",
            build: "100",
            releaseNotes: nil,
            informationURL: nil
        )
        presenter.downloadDidBegin(update)
        for _ in 0..<4 { await Task.yield() }

        var visible = runtime.instances(
            capabilities: [.persistentSidebar, .directSoftwareUpdates]
        )
        guard
            case .softwareUpdate(let downloading) = try XCTUnwrap(visible.first).presentation
        else { return XCTFail("Expected the download in the sidebar runtime") }
        XCTAssertEqual(downloading.phase, .downloading)

        presenter.installationDidBecomeReady(update, installAndRelaunch: {})
        for _ in 0..<4 { await Task.yield() }

        visible = runtime.instances(
            capabilities: [.persistentSidebar, .directSoftwareUpdates]
        )
        guard case .softwareUpdate(let ready) = try XCTUnwrap(visible.first).presentation
        else { return XCTFail("Expected the ready update in the sidebar runtime") }
        XCTAssertEqual(ready.phase, .readyToInstall)
        XCTAssertEqual(visible.first?.availableActions, [.installAndRelaunch])
    }

    func testSidebarWidgetRoutesPermissionAndStatusActions() async throws {
        let source = BrowserSoftwareUpdateWidgetSource()
        let model = BrowserSoftwareUpdateModel(widgetSource: source)
        var iterator = source.events().makeAsyncIterator()
        _ = await iterator.next()
        var automaticChecksChoice: Bool?
        var acknowledgementCount = 0

        model.presentPermissionRequest { automaticChecksChoice = $0 }
        let permissionEmission = await iterator.next()
        let permission = try XCTUnwrap(permissionEmission?.first)
        XCTAssertEqual(
            permission.availableActions,
            [.declineAutomaticUpdateChecks, .enableAutomaticUpdateChecks]
        )

        source.perform(.enableAutomaticUpdateChecks, on: permission.id)
        XCTAssertEqual(automaticChecksChoice, true)
        let dismissedPermission = await iterator.next()
        XCTAssertEqual(dismissedPermission, [])

        model.presentNoUpdate(
            message: "Crest is up to date.",
            acknowledgement: { acknowledgementCount += 1 }
        )
        let statusEmission = await iterator.next()
        let status = try XCTUnwrap(statusEmission?.first)
        XCTAssertEqual(status.availableActions, [.acknowledgeUpdateStatus])

        source.perform(.acknowledgeUpdateStatus, on: status.id)
        XCTAssertEqual(acknowledgementCount, 1)
        let dismissedStatus = await iterator.next()
        XCTAssertEqual(dismissedStatus, [])
    }

    func testManuallyFoundUpdateStaysWidgetActionableUntilChoice() async throws {
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

        XCTAssertEqual(model.phase, .updateAvailable)
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

    func testBackgroundDiscoveryPublishesWidget() async throws {
        let source = BrowserSoftwareUpdateWidgetSource()
        let model = BrowserSoftwareUpdateModel(widgetSource: source)
        var iterator = source.events().makeAsyncIterator()
        _ = await iterator.next()

        model.presentUpdate(
            title: "Crest 1.0",
            version: "1.0.0",
            build: "100",
            isInformationOnly: false,
            install: {},
            skip: {}
        )

        let backgroundEmission = await iterator.next()
        XCTAssertNotNil(backgroundEmission?.first)
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

    func testIsolatedSidebarFixturePublishesOnlyTheWidgetState() async throws {
        let service = BrowserSoftwareUpdateService(
            isEnabled: false,
            preferences: nil
        )
        var iterator = service.widgetSource.events().makeAsyncIterator()
        _ = await iterator.next()

        service.presentIsolatedSidebarWidgetFixture("available:0.5.99:599")

        let emission = await iterator.next()
        let instance = try XCTUnwrap(emission?.first)
        XCTAssertEqual(instance.id.instanceID, "599")
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
        source.perform(.acknowledgeUpdateStatus, on: failed.id)
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
