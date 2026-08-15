import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionNotificationServiceTests: XCTestCase {
    private enum Fixture {
        static let alpha = BrowserExtensionServiceClientID("alpha-extension")
        static let beta = BrowserExtensionServiceClientID("beta-extension")
    }

    private struct CenterFailure: Error, LocalizedError {
        var errorDescription: String? { "The center refused the notification." }
    }

    // MARK: - Identity encoding

    func testIdentityRoundTripsThroughTheSystemIdentifier() throws {
        let identity = BrowserExtensionNotificationIdentity(
            client: try XCTUnwrap(Fixture.alpha),
            notificationIdentifier: "update-available"
        )

        let systemIdentifier =
            BrowserExtensionNotificationIdentityCodec
            .systemIdentifier(for: identity)

        XCTAssertEqual(
            BrowserExtensionNotificationIdentityCodec
                .identity(fromSystemIdentifier: systemIdentifier),
            identity
        )
    }

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

    func testUnrelatedSystemIdentifiersDecodeToNothing() {
        XCTAssertNil(
            BrowserExtensionNotificationIdentityCodec
                .identity(fromSystemIdentifier: "com.example.other-notification")
        )
        XCTAssertNil(
            BrowserExtensionNotificationIdentityCodec.identity(
                fromSystemIdentifier: "crest.webextension.notification.notanumber.x"
            )
        )
    }

    func testCategoryIdentifierRoundTripsAndDiffersFromTheSystemIdentifier()
        throws
    {
        let identity = BrowserExtensionNotificationIdentity(
            client: try XCTUnwrap(Fixture.alpha),
            notificationIdentifier: "sync-finished"
        )

        let categoryIdentifier =
            BrowserExtensionNotificationIdentityCodec
            .categoryIdentifier(for: identity)

        XCTAssertNotEqual(
            categoryIdentifier,
            BrowserExtensionNotificationIdentityCodec.systemIdentifier(for: identity)
        )
        XCTAssertEqual(
            BrowserExtensionNotificationIdentityCodec
                .identity(fromCategoryIdentifier: categoryIdentifier),
            identity
        )
        XCTAssertNil(
            BrowserExtensionNotificationIdentityCodec
                .identity(fromSystemIdentifier: categoryIdentifier)
        )
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

    func testRepostingTheSameIdentifierReplacesTheDelivery() async throws {
        let center = InMemoryBrowserExtensionNotificationCenter()
        let service = BrowserExtensionNotificationService(center: center)
        let client = try XCTUnwrap(Fixture.alpha)

        await service.post(
            BrowserExtensionNotificationRequest(
                identifier: "progress",
                title: "Working",
                message: "Ten percent."
            ),
            from: client
        )
        await service.post(
            BrowserExtensionNotificationRequest(
                identifier: "progress",
                title: "Working",
                message: "Ninety percent."
            ),
            from: client
        )

        XCTAssertEqual(center.deliveries.count, 1)
        XCTAssertEqual(center.deliveries.first?.body, "Ninety percent.")
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

    func testAPromptThatEndsDeniedSuppressesTheDelivery() async throws {
        let center = InMemoryBrowserExtensionNotificationCenter(
            authorization: .notDetermined,
            authorizationAfterPrompt: .denied
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
    }

    func testARejectedDeliveryReportsTheHostDescription() async throws {
        let center = InMemoryBrowserExtensionNotificationCenter()
        center.addFailure = CenterFailure()
        let service = BrowserExtensionNotificationService(center: center)

        let outcome = await service.post(
            BrowserExtensionNotificationRequest(
                identifier: "rejected",
                title: "Rejected",
                message: "Never shown."
            ),
            from: try XCTUnwrap(Fixture.alpha)
        )

        XCTAssertEqual(
            outcome,
            .rejected(description: "The center refused the notification.")
        )
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

    func testEveryEventStreamForOneExtensionReceivesTheInteraction()
        async throws
    {
        let center = InMemoryBrowserExtensionNotificationCenter()
        let service = BrowserExtensionNotificationService(center: center)
        let client = try XCTUnwrap(Fixture.alpha)

        var first = service.events(for: client).makeAsyncIterator()
        var second = service.events(for: client).makeAsyncIterator()

        let outcome = await service.post(
            BrowserExtensionNotificationRequest(
                identifier: "closable",
                title: "Closable",
                message: "Dismiss me."
            ),
            from: client
        )
        let identity = try XCTUnwrap(outcome.presentedIdentity)

        center.simulate(
            BrowserExtensionNotificationSystemEvent(
                systemIdentifier:
                    BrowserExtensionNotificationIdentityCodec
                    .systemIdentifier(for: identity),
                kind: .dismissed(byUser: true)
            )
        )

        let firstEvent = await first.next()
        let secondEvent = await second.next()
        XCTAssertEqual(firstEvent?.kind, .dismissed(byUser: true))
        XCTAssertEqual(secondEvent?.kind, .dismissed(byUser: true))
    }

    func testInteractionsWithForeignNotificationsAreIgnored() async throws {
        let center = InMemoryBrowserExtensionNotificationCenter()
        let service = BrowserExtensionNotificationService(center: center)
        let client = try XCTUnwrap(Fixture.alpha)
        var events = service.events(for: client).makeAsyncIterator()

        center.simulate(
            BrowserExtensionNotificationSystemEvent(
                systemIdentifier: "com.example.unrelated",
                kind: .clicked
            )
        )
        let outcome = await service.post(
            BrowserExtensionNotificationRequest(
                identifier: "real",
                title: "Real",
                message: "Shown."
            ),
            from: client
        )
        let identity = try XCTUnwrap(outcome.presentedIdentity)
        center.simulate(
            BrowserExtensionNotificationSystemEvent(
                systemIdentifier:
                    BrowserExtensionNotificationIdentityCodec
                    .systemIdentifier(for: identity),
                kind: .clicked
            )
        )

        let received = await events.next()
        XCTAssertEqual(received?.identity, identity)
    }
}
