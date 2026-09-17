import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionNotificationServiceTests: XCTestCase {
    private enum Fixture {
        static let alpha = BrowserExtensionServiceClientID("alpha-extension")
        static let beta = BrowserExtensionServiceClientID("beta-extension")
    }

    // MARK: - Identity encoding

    /// An extension chooses its own notification identifiers, so it must not be
    /// able to spell one that decodes as another extension's notification.
    func testNotificationIdentifierCannotForgeAnotherClient() throws {
        let alpha = try XCTUnwrap(Fixture.alpha)
        let beta = try XCTUnwrap(Fixture.beta)
        let forged = BrowserExtensionNotificationIdentity(
            client: alpha,
            notificationIdentifier: ".\(beta.rawValue).spoofed"
        )

        let decoded = BrowserExtensionNotificationIdentityCodec.identity(
            fromSystemIdentifier:
                BrowserExtensionNotificationIdentityCodec
                .systemIdentifier(for: forged)
        )

        XCTAssertEqual(decoded?.client, alpha)
        XCTAssertEqual(decoded?.notificationIdentifier, ".\(beta.rawValue).spoofed")
    }

    // MARK: - Posting

    func testPostingCarriesTitleButtonsAndPerClientThread() async throws {
        let center = InMemoryBrowserExtensionNotificationCenter()
        let service = BrowserExtensionNotificationService(center: center)
        let client = try XCTUnwrap(Fixture.alpha)

        let outcome = await service.post(
            BrowserExtensionNotificationRequest(
                identifier: "update-available",
                title: "Update ready",
                message: "Version 2 is available.",
                buttonTitles: ["Install", "Later"]
            ),
            from: client
        )

        let identity = try XCTUnwrap(outcome.presentedIdentity)
        XCTAssertEqual(identity.client, client)
        XCTAssertEqual(identity.notificationIdentifier, "update-available")

        let delivery = try XCTUnwrap(center.deliveries.first)
        XCTAssertEqual(delivery.title, "Update ready")
        XCTAssertEqual(delivery.body, "Version 2 is available.")
        XCTAssertEqual(delivery.buttonTitles, ["Install", "Later"])
        XCTAssertEqual(
            delivery.threadIdentifier,
            BrowserExtensionNotificationIdentityCodec.threadIdentifier(for: client)
        )
    }

    func testTwoExtensionsMayShareANotificationIdentifier() async throws {
        let center = InMemoryBrowserExtensionNotificationCenter()
        let service = BrowserExtensionNotificationService(center: center)
        let alpha = try XCTUnwrap(Fixture.alpha)
        let beta = try XCTUnwrap(Fixture.beta)

        await service.post(
            BrowserExtensionNotificationRequest(
                identifier: "shared",
                title: "Alpha",
                message: "From alpha."
            ),
            from: alpha
        )
        await service.post(
            BrowserExtensionNotificationRequest(
                identifier: "shared",
                title: "Beta",
                message: "From beta."
            ),
            from: beta
        )

        XCTAssertEqual(center.deliveries.count, 2)
        let alphaIdentifiers = await service.presentedNotificationIdentifiers(
            for: alpha
        )
        let betaIdentifiers = await service.presentedNotificationIdentifiers(
            for: beta
        )
        XCTAssertEqual(alphaIdentifiers, ["shared"])
        XCTAssertEqual(betaIdentifiers, ["shared"])
    }

    // MARK: - Authorization

    func testDeniedAuthorizationReturnsAnOutcomeInsteadOfThrowing() async throws {
        let center = InMemoryBrowserExtensionNotificationCenter(
            authorization: .denied
        )
        let service = BrowserExtensionNotificationService(center: center)

        let outcome = await service.post(
            BrowserExtensionNotificationRequest(
                identifier: "blocked",
                title: "Blocked",
                message: "Never shown."
            ),
            from: try XCTUnwrap(Fixture.alpha)
        )

        XCTAssertEqual(outcome, .authorizationDenied)
        XCTAssertTrue(center.deliveries.isEmpty)
        XCTAssertEqual(center.authorizationPromptCount, 0)
    }

    func testUndeterminedAuthorizationPromptsOnceThenDelivers() async throws {
        let center = InMemoryBrowserExtensionNotificationCenter(
            authorization: .notDetermined,
            authorizationAfterPrompt: .authorized
        )
        let service = BrowserExtensionNotificationService(center: center)
        let client = try XCTUnwrap(Fixture.alpha)

        let first = await service.post(
            BrowserExtensionNotificationRequest(
                identifier: "one",
                title: "One",
                message: "First."
            ),
            from: client
        )
        let second = await service.post(
            BrowserExtensionNotificationRequest(
                identifier: "two",
                title: "Two",
                message: "Second."
            ),
            from: client
        )

        XCTAssertNotNil(first.presentedIdentity)
        XCTAssertNotNil(second.presentedIdentity)
        XCTAssertEqual(center.authorizationPromptCount, 1)
    }

    // MARK: - Updating

    /// Chrome's `update` is a partial edit, so an extension that changes only
    /// the message keeps the title and buttons it posted with.
    func testUpdatingOneFieldKeepsEverythingItDidNotMention() async throws {
        let center = InMemoryBrowserExtensionNotificationCenter()
        let service = BrowserExtensionNotificationService(center: center)
        let client = try XCTUnwrap(Fixture.alpha)
        await service.post(
            BrowserExtensionNotificationRequest(
                identifier: "sync",
                title: "Syncing",
                message: "Ten percent.",
                iconData: Data([0x01]),
                buttonTitles: ["Pause", "Cancel"]
            ),
            from: client
        )

        let outcome = await service.update(
            BrowserExtensionNotificationUpdate(
                identifier: "sync",
                message: "Ninety percent."
            ),
            from: client
        )

        XCTAssertEqual(outcome, .updated)
        let delivery = try XCTUnwrap(center.deliveries.first)
        XCTAssertEqual(delivery.title, "Syncing")
        XCTAssertEqual(delivery.body, "Ninety percent.")
        XCTAssertEqual(delivery.buttonTitles, ["Pause", "Cancel"])
        XCTAssertEqual(delivery.iconData, Data([0x01]))
        XCTAssertEqual(center.deliveries.count, 1)
    }

    /// One extension's notification identifiers are invisible to another, so
    /// `update` cannot be used to edit — or to discover — someone else's.
    func testOneExtensionCannotUpdateAnothersNotification() async throws {
        let center = InMemoryBrowserExtensionNotificationCenter()
        let service = BrowserExtensionNotificationService(center: center)
        let alpha = try XCTUnwrap(Fixture.alpha)
        let beta = try XCTUnwrap(Fixture.beta)
        await service.post(
            BrowserExtensionNotificationRequest(
                identifier: "shared",
                title: "Alpha",
                message: "From alpha."
            ),
            from: alpha
        )

        let outcome = await service.update(
            BrowserExtensionNotificationUpdate(
                identifier: "shared",
                title: "Beta"
            ),
            from: beta
        )

        XCTAssertEqual(outcome, .unknownNotification)
        XCTAssertEqual(center.deliveries.count, 1)
        XCTAssertEqual(center.deliveries.first?.title, "Alpha")
    }

    /// A notification that has left the screen is not editable: `update` says
    /// so rather than quietly presenting it again.
    func testUpdatingAClearedOrDismissedNotificationReportsItIsGone()
        async throws
    {
        let center = InMemoryBrowserExtensionNotificationCenter()
        let service = BrowserExtensionNotificationService(center: center)
        let client = try XCTUnwrap(Fixture.alpha)
        await service.post(
            BrowserExtensionNotificationRequest(
                identifier: "cleared",
                title: "Cleared",
                message: "Gone."
            ),
            from: client
        )
        await service.post(
            BrowserExtensionNotificationRequest(
                identifier: "dismissed",
                title: "Dismissed",
                message: "Gone too."
            ),
            from: client
        )
        await service.clear(notificationIdentifier: "cleared", from: client)
        center.simulate(
            BrowserExtensionNotificationSystemEvent(
                systemIdentifier:
                    BrowserExtensionNotificationIdentityCodec
                    .systemIdentifier(
                        for: BrowserExtensionNotificationIdentity(
                            client: client,
                            notificationIdentifier: "dismissed"
                        )
                    ),
                kind: .dismissed(byUser: true)
            )
        )
        await center.removeDelivered(
            systemIdentifiers: [
                BrowserExtensionNotificationIdentityCodec.systemIdentifier(
                    for: BrowserExtensionNotificationIdentity(
                        client: client,
                        notificationIdentifier: "dismissed"
                    )
                )
            ]
        )

        let cleared = await service.update(
            BrowserExtensionNotificationUpdate(
                identifier: "cleared",
                message: "Back?"
            ),
            from: client
        )
        let dismissed = await service.update(
            BrowserExtensionNotificationUpdate(
                identifier: "dismissed",
                message: "Back?"
            ),
            from: client
        )

        XCTAssertEqual(cleared, .unknownNotification)
        XCTAssertEqual(dismissed, .unknownNotification)
        XCTAssertTrue(center.deliveries.isEmpty)
    }

    // MARK: - Clearing and enumeration

    func testClearingReportsWhetherTheNotificationWasPresented() async throws {
        let center = InMemoryBrowserExtensionNotificationCenter()
        let service = BrowserExtensionNotificationService(center: center)
        let client = try XCTUnwrap(Fixture.alpha)

        await service.post(
            BrowserExtensionNotificationRequest(
                identifier: "present",
                title: "Present",
                message: "Shown."
            ),
            from: client
        )

        let cleared = await service.clear(
            notificationIdentifier: "present",
            from: client
        )
        let clearedAgain = await service.clear(
            notificationIdentifier: "present",
            from: client
        )

        XCTAssertTrue(cleared)
        XCTAssertFalse(clearedAgain)
        XCTAssertTrue(center.deliveries.isEmpty)
    }

    func testOneExtensionCannotClearAnothersNotification() async throws {
        let center = InMemoryBrowserExtensionNotificationCenter()
        let service = BrowserExtensionNotificationService(center: center)
        let alpha = try XCTUnwrap(Fixture.alpha)
        let beta = try XCTUnwrap(Fixture.beta)

        await service.post(
            BrowserExtensionNotificationRequest(
                identifier: "shared",
                title: "Alpha",
                message: "From alpha."
            ),
            from: alpha
        )

        let cleared = await service.clear(
            notificationIdentifier: "shared",
            from: beta
        )
        await service.clearAll(from: beta)

        XCTAssertFalse(cleared)
        XCTAssertEqual(center.deliveries.count, 1)
    }

    func testClearAllWithdrawsOnlyTheRequestingExtensionsNotifications()
        async throws
    {
        let center = InMemoryBrowserExtensionNotificationCenter()
        let service = BrowserExtensionNotificationService(center: center)
        let alpha = try XCTUnwrap(Fixture.alpha)
        let beta = try XCTUnwrap(Fixture.beta)

        await service.post(
            BrowserExtensionNotificationRequest(
                identifier: "one",
                title: "One",
                message: "First."
            ),
            from: alpha
        )
        await service.post(
            BrowserExtensionNotificationRequest(
                identifier: "two",
                title: "Two",
                message: "Second."
            ),
            from: alpha
        )
        await service.post(
            BrowserExtensionNotificationRequest(
                identifier: "kept",
                title: "Kept",
                message: "Third."
            ),
            from: beta
        )

        await service.clearAll(from: alpha)

        let alphaIdentifiers = await service.presentedNotificationIdentifiers(
            for: alpha
        )
        let betaIdentifiers = await service.presentedNotificationIdentifiers(
            for: beta
        )
        XCTAssertTrue(alphaIdentifiers.isEmpty)
        XCTAssertEqual(betaIdentifiers, ["kept"])
    }

    /// `getAll` reads the host back rather than trusting local bookkeeping, so a
    /// notification the person dismissed themselves disappears from the list.
    func testEnumerationFollowsTheHostRatherThanLocalBookkeeping() async throws {
        let center = InMemoryBrowserExtensionNotificationCenter()
        let service = BrowserExtensionNotificationService(center: center)
        let client = try XCTUnwrap(Fixture.alpha)

        await service.post(
            BrowserExtensionNotificationRequest(
                identifier: "dismissed-elsewhere",
                title: "Gone",
                message: "Dismissed by the person."
            ),
            from: client
        )
        // The person dismisses it from Notification Center: the host drops it
        // without the service being told.
        await center.removeDelivered(
            systemIdentifiers: center.deliveries.map(\.systemIdentifier)
        )

        let identifiers = await service.presentedNotificationIdentifiers(
            for: client
        )
        XCTAssertTrue(identifiers.isEmpty)
    }

    // MARK: - Events

    func testInteractionsReachOnlyTheOwningExtension() async throws {
        let center = InMemoryBrowserExtensionNotificationCenter()
        let service = BrowserExtensionNotificationService(center: center)
        let alpha = try XCTUnwrap(Fixture.alpha)
        let beta = try XCTUnwrap(Fixture.beta)

        var alphaEvents = service.events(for: alpha).makeAsyncIterator()
        var betaEvents = service.events(for: beta).makeAsyncIterator()

        let alphaOutcome = await service.post(
            BrowserExtensionNotificationRequest(
                identifier: "clickable",
                title: "Clickable",
                message: "Tap me.",
                buttonTitles: ["Install"]
            ),
            from: alpha
        )
        let betaOutcome = await service.post(
            BrowserExtensionNotificationRequest(
                identifier: "clickable",
                title: "Clickable",
                message: "Tap me too."
            ),
            from: beta
        )
        let alphaIdentity = try XCTUnwrap(alphaOutcome.presentedIdentity)
        let betaIdentity = try XCTUnwrap(betaOutcome.presentedIdentity)

        center.simulate(
            BrowserExtensionNotificationSystemEvent(
                systemIdentifier:
                    BrowserExtensionNotificationIdentityCodec
                    .systemIdentifier(for: alphaIdentity),
                kind: .buttonClicked(index: 0)
            )
        )
        center.simulate(
            BrowserExtensionNotificationSystemEvent(
                systemIdentifier:
                    BrowserExtensionNotificationIdentityCodec
                    .systemIdentifier(for: betaIdentity),
                kind: .clicked
            )
        )

        let alphaReceived = await alphaEvents.next()
        XCTAssertEqual(
            alphaReceived,
            BrowserExtensionNotificationEvent(
                identity: alphaIdentity,
                kind: .buttonClicked(index: 0)
            )
        )

        // Beta's first event is its own, proving alpha's interaction — which was
        // simulated first — never entered beta's stream.
        let betaReceived = await betaEvents.next()
        XCTAssertEqual(
            betaReceived,
            BrowserExtensionNotificationEvent(
                identity: betaIdentity,
                kind: .clicked
            )
        )
    }

}
