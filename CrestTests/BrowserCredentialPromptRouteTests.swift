import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCredentialPromptRouteTests: XCTestCase {
    func testEveryCredentialPhaseMapsToOneExactRoute() {
        let expectations:
            [(
                phase: BrowserCredentialSavePromptPhase,
                state: BrowserCredentialPromptState,
                primaryAction: BrowserCredentialPromptPrimaryAction?,
                dismissAction: BrowserCredentialPromptDismissAction,
                busyActivity: BrowserCredentialPromptBusyActivity?
            )] = [
                (.preparing, .preparing, nil, .notNow, .checkingSavedPasswords),
                (.create, .create, .commit(.create), .notNow, nil),
                (.update, .update, .commit(.update), .notNow, nil),
                (.alreadyStored, .alreadyStored, nil, .notNow, nil),
                (.saving(.create), .saving(.create), nil, .notNow, .savingPassword),
                (.saving(.update), .saving(.update), nil, .notNow, .savingPassword),
                (.saved(.created), .saved(.created), nil, .done, nil),
                (.failed(.preparation), .failedPreparation, .retryCredentialPreparation, .notNow, nil),
                (
                    .failed(.commit(.create)),
                    .failedCommit(.create),
                    .retryCredentialPreparation,
                    .notNow,
                    nil
                ),
                (
                    .failed(.commit(.update)),
                    .failedCommit(.update),
                    .retryCredentialPreparation,
                    .notNow,
                    nil
                ),
            ]

        for expectation in expectations {
            let route = BrowserCredentialPromptRoute(
                phase: expectation.phase,
                systemPasswordOfferPhase: .notRequested,
                offersSystemPasswords: false
            )

            XCTAssertEqual(route.state, expectation.state)
            XCTAssertEqual(route.primaryAction, expectation.primaryAction)
            XCTAssertEqual(route.dismissAction, expectation.dismissAction)
            XCTAssertEqual(route.busyActivity, expectation.busyActivity)
            XCTAssertEqual(route.isBusy, expectation.busyActivity != nil)
        }
    }

    func testSystemPasswordOfferPhasesRouteOnlyAfterTheCrestSave() {
        let expectations:
            [(
                phase: BrowserSystemPasswordOfferPhase,
                state: BrowserCredentialPromptState,
                primaryAction: BrowserCredentialPromptPrimaryAction?,
                busyActivity: BrowserCredentialPromptBusyActivity?
            )] = [
                (.notRequested, .saved(.updated), nil, nil),
                (.offering, .offeringToSystemPasswords, nil, .openingSystemPasswords),
                (.completed, .completedSystemPasswords, nil, nil),
                (.failed, .failedSystemPasswords, .retrySystemPasswords, nil),
            ]

        for expectation in expectations {
            let route = BrowserCredentialPromptRoute(
                phase: .saved(.updated),
                systemPasswordOfferPhase: expectation.phase,
                offersSystemPasswords: true
            )

            XCTAssertEqual(route.state, expectation.state)
            XCTAssertEqual(route.primaryAction, expectation.primaryAction)
            XCTAssertEqual(route.busyActivity, expectation.busyActivity)
            XCTAssertEqual(route.dismissAction, .done)
        }

        for systemPhase in [
            BrowserSystemPasswordOfferPhase.notRequested,
            .offering,
            .completed,
            .failed,
        ] {
            let route = BrowserCredentialPromptRoute(
                phase: .create,
                systemPasswordOfferPhase: systemPhase,
                offersSystemPasswords: true
            )
            XCTAssertEqual(route.state, .create)
            XCTAssertEqual(route.primaryAction, .commit(.create))
        }
    }

    func testMacAndMobileRoutesShareCoreStateWhileKeepingRealPlatformDifferencesTyped() throws {
        let macRoute = BrowserCredentialPromptRoute(
            phase: .update,
            systemPasswordOfferPhase: .notRequested,
            offersSystemPasswords: false
        )
        let mobileRoute = BrowserCredentialPromptRoute(
            phase: .update,
            systemPasswordOfferPhase: .notRequested,
            offersSystemPasswords: true
        )

        XCTAssertEqual(macRoute.state, mobileRoute.state)
        XCTAssertEqual(macRoute.primaryAction, mobileRoute.primaryAction)
        XCTAssertEqual(macRoute.dismissAction, mobileRoute.dismissAction)
        XCTAssertEqual(
            localized(macRoute.title(spaceName: "Work"), localeIdentifier: "en"),
            localized(mobileRoute.title(spaceName: "Work"), localeIdentifier: "en")
        )
        XCTAssertEqual(
            localized(
                try XCTUnwrap(macRoute.primaryActionTitle(spaceName: "Work")),
                localeIdentifier: "en"
            ),
            "Update in Work"
        )
        XCTAssertEqual(
            localized(
                try XCTUnwrap(mobileRoute.primaryActionTitle(spaceName: "Work")),
                localeIdentifier: "en"
            ),
            "Update & Offer to Passwords"
        )
    }

    func testDestinationMetadataPreservesSeparateAndCombinedSyncPresentation() {
        let route = BrowserCredentialPromptRoute(
            phase: .create,
            systemPasswordOfferPhase: .notRequested,
            offersSystemPasswords: false
        )
        let macDestination = route.destinationMetadata(
            spaceName: "Work",
            syncsWithICloud: true,
            presentation: .separateSyncStatus
        )
        let mobileDestination = route.destinationMetadata(
            spaceName: "Work",
            syncsWithICloud: true,
            presentation: .combinedStatus
        )

        XCTAssertEqual(
            localized(macDestination.detail, localeIdentifier: "en"),
            "Stored only in the Work Space"
        )
        XCTAssertEqual(
            localized(try XCTUnwrap(macDestination.syncStatus), localeIdentifier: "en"),
            "Crest iCloud sync on"
        )
        XCTAssertEqual(
            localized(mobileDestination.detail, localeIdentifier: "en"),
            "Stored only in Work, with Crest iCloud sync"
        )
        XCTAssertNil(mobileDestination.syncStatus)
    }

    func testPresentationCopyResolvesExactlyInEnglishAndArabic() throws {
        let create = BrowserCredentialPromptRoute(
            phase: .create,
            systemPasswordOfferPhase: .notRequested,
            offersSystemPasswords: false
        )
        let update = BrowserCredentialPromptRoute(
            phase: .update,
            systemPasswordOfferPhase: .notRequested,
            offersSystemPasswords: true
        )
        let preparationFailure = BrowserCredentialPromptRoute(
            phase: .failed(.preparation),
            systemPasswordOfferPhase: .notRequested,
            offersSystemPasswords: false
        )
        let systemFailure = BrowserCredentialPromptRoute(
            phase: .saved(.created),
            systemPasswordOfferPhase: .failed,
            offersSystemPasswords: true
        )
        let frameOrigin = try XCTUnwrap(
            CredentialOrigin(url: try XCTUnwrap(URL(string: "https://login.example.com")))
        )
        let topLevelOrigin = try XCTUnwrap(
            CredentialOrigin(url: try XCTUnwrap(URL(string: "https://example.com")))
        )
        let isolatedWork = "\u{2068}Work\u{2069}"
        let isolatedFrameOrigin = "\u{2068}https://login.example.com\u{2069}"
        let isolatedTopLevelOrigin = "\u{2068}https://example.com\u{2069}"

        let expectations:
            [(
                resource: LocalizedStringResource,
                english: String,
                arabic: String
            )] = [
                (create.title(spaceName: "Work"), "Save password?", "هل تريد حفظ كلمة المرور؟"),
                (
                    try XCTUnwrap(create.primaryActionTitle(spaceName: "Work")),
                    "Save in Work",
                    "حفظ في \(isolatedWork)"
                ),
                (
                    try XCTUnwrap(update.primaryActionTitle(spaceName: "Work")),
                    "Update & Offer to Passwords",
                    "تحديث وعرض نسخة على «كلمات السر»"
                ),
                (
                    preparationFailure.title(spaceName: "Work"),
                    "Couldn’t check password",
                    "تعذّر التحقق من كلمة المرور"
                ),
                (
                    try XCTUnwrap(preparationFailure.errorMessage(spaceName: "Work")),
                    "Crest couldn’t check this Space’s saved passwords.",
                    "تعذّر على Crest التحقق من كلمات المرور المحفوظة في هذه المساحة."
                ),
                (
                    systemFailure.title(spaceName: "Work"),
                    "Saved in Work",
                    "تم الحفظ في \(isolatedWork)"
                ),
                (
                    try XCTUnwrap(systemFailure.errorMessage(spaceName: "Work")),
                    "Saved in Work. The Passwords offer wasn’t completed.",
                    "تم الحفظ في \(isolatedWork). لم يكتمل عرض النسخة على «كلمات السر»."
                ),
                (
                    create.crossOriginMessage(
                        frameOrigin: frameOrigin,
                        topLevelOrigin: topLevelOrigin,
                        subject: .currentCredential
                    ),
                    "This credential belongs to the embedded https://login.example.com frame, not https://example.com.",
                    "تنتمي بيانات الاعتماد هذه إلى إطار \(isolatedFrameOrigin) المضمّن، وليس إلى \(isolatedTopLevelOrigin)."
                ),
                (
                    create.crossOriginMessage(
                        frameOrigin: frameOrigin,
                        topLevelOrigin: topLevelOrigin,
                        subject: .definiteCredential
                    ),
                    "The credential belongs to the embedded https://login.example.com frame, not https://example.com.",
                    "تنتمي بيانات الاعتماد إلى إطار \(isolatedFrameOrigin) المضمّن، وليس إلى \(isolatedTopLevelOrigin)."
                ),
            ]

        for expectation in expectations {
            XCTAssertEqual(
                localized(expectation.resource, localeIdentifier: "en"),
                expectation.english
            )
            XCTAssertEqual(
                localized(expectation.resource, localeIdentifier: "ar"),
                expectation.arabic
            )
        }
    }

    func testMissingSpaceUsesWholeLocalizedFallbackPhrases() throws {
        let route = BrowserCredentialPromptRoute(
            phase: .create,
            systemPasswordOfferPhase: .notRequested,
            offersSystemPasswords: false
        )
        let destination = route.destinationMetadata(
            spaceName: nil,
            syncsWithICloud: false,
            presentation: .combinedStatus
        )

        XCTAssertEqual(
            localized(
                try XCTUnwrap(route.primaryActionTitle(spaceName: nil)),
                localeIdentifier: "en"
            ),
            "Save in this Space"
        )
        XCTAssertEqual(
            localized(destination.detail, localeIdentifier: "en"),
            "Stored only in this Space"
        )
        XCTAssertFalse(localized(destination.detail, localeIdentifier: "en").contains("Space Space"))
    }

    func testMacBannerMetadataResolvesBusyFailureAndDestinationCopyInEnglishAndArabic() throws {
        let preparing = BrowserCredentialPromptRoute(
            phase: .preparing,
            systemPasswordOfferPhase: .notRequested,
            offersSystemPasswords: false
        )
        let failure = BrowserCredentialPromptRoute(
            phase: .failed(.commit(.update)),
            systemPasswordOfferPhase: .notRequested,
            offersSystemPasswords: false
        )
        let destination = failure.destinationMetadata(
            spaceName: "Work",
            syncsWithICloud: true,
            presentation: .separateSyncStatus
        )
        let isolatedWork = "\u{2068}Work\u{2069}"

        let expectations: [(resource: LocalizedStringResource, english: String, arabic: String)] = [
            (
                try XCTUnwrap(preparing.busyAccessibilityLabel),
                "Checking saved passwords",
                "جارٍ التحقق من كلمات المرور المحفوظة"
            ),
            (failure.title(spaceName: "Work"), "Update password?", "هل تريد تحديث كلمة المرور؟"),
            (
                try XCTUnwrap(failure.primaryActionTitle(spaceName: "Work")),
                "Try Again",
                "المحاولة مجددًا"
            ),
            (failure.dismissActionTitle, "Not Now", "ليس الآن"),
            (
                try XCTUnwrap(failure.errorMessage(spaceName: "Work")),
                "Crest couldn’t save this password to the Work Space.",
                "تعذّر على Crest حفظ كلمة المرور هذه في مساحة \(isolatedWork)."
            ),
            (
                destination.detail,
                "Stored only in the Work Space",
                "مخزّنة في مساحة \(isolatedWork) فقط"
            ),
            (
                try XCTUnwrap(destination.syncStatus),
                "Crest iCloud sync on",
                "مزامنة Crest عبر iCloud مفعّلة"
            ),
        ]

        for expectation in expectations {
            XCTAssertEqual(
                localized(expectation.resource, localeIdentifier: "en"),
                expectation.english
            )
            XCTAssertEqual(
                localized(expectation.resource, localeIdentifier: "ar"),
                expectation.arabic
            )
        }
    }

    func testReplacingPromptWhileSystemOfferIsSuspendedCannotMutateTheReplacementSpace() async throws {
        let store = BrowserStore(
            session: .preview,
            persistence: InMemoryBrowserSessionPersistence(),
            credentialVault: InMemoryCredentialVault()
        )
        let firstSpace = try XCTUnwrap(store.session.spaces.first)
        let replacementSpace = try XCTUnwrap(store.session.spaces.dropFirst().first)
        let origin = try XCTUnwrap(
            CredentialOrigin(url: try XCTUnwrap(URL(string: "https://accounts.crest.test/login")))
        )
        let firstCandidate = BrowserCredentialSaveCandidate(
            id: UUID(),
            origin: origin,
            topLevelOrigin: origin,
            username: "first@example.com",
            password: "first-secret",
            passwordKind: .current,
            isCrossOriginFrame: false,
            submittedAt: Date(timeIntervalSince1970: 4_000)
        )
        let replacementCandidate = BrowserCredentialSaveCandidate(
            id: UUID(),
            origin: origin,
            topLevelOrigin: origin,
            username: "replacement@example.com",
            password: "replacement-secret",
            passwordKind: .current,
            isCrossOriginFrame: false,
            submittedAt: Date(timeIntervalSince1970: 4_100)
        )
        let model = BrowserCredentialSavePromptModel()
        let offerStarted = expectation(description: "system Passwords offer started")
        let suspension = SystemPasswordOfferSuspension()

        await model.prepare(
            candidate: firstCandidate,
            in: firstSpace.id,
            browser: store,
            now: firstCandidate.submittedAt
        )
        await model.commit(
            candidate: firstCandidate,
            in: firstSpace.id,
            browser: store,
            now: firstCandidate.submittedAt
        )

        let staleOffer = Task { @MainActor in
            await model.offerToSystemPasswords {
                offerStarted.fulfill()
                await suspension.wait()
            }
        }
        await fulfillment(of: [offerStarted])

        await model.prepare(
            candidate: replacementCandidate,
            in: replacementSpace.id,
            browser: store,
            now: replacementCandidate.submittedAt
        )
        XCTAssertEqual(model.phase, .create)
        XCTAssertEqual(model.systemPasswordOfferPhase, .notRequested)

        await suspension.resume()
        await staleOffer.value

        XCTAssertEqual(model.phase, .create)
        XCTAssertEqual(model.systemPasswordOfferPhase, .notRequested)

        await model.commit(
            candidate: firstCandidate,
            in: firstSpace.id,
            browser: store,
            now: firstCandidate.submittedAt
        )
        XCTAssertEqual(model.phase, .create)

        await model.commit(
            candidate: replacementCandidate,
            in: replacementSpace.id,
            browser: store,
            now: replacementCandidate.submittedAt
        )
        XCTAssertEqual(model.phase, .saved(.created))
        let firstSpaceDescriptors = try await store.savedCredentialDescriptors(in: firstSpace.id)
        let replacementSpaceDescriptors = try await store.savedCredentialDescriptors(
            in: replacementSpace.id
        )
        XCTAssertEqual(firstSpaceDescriptors.count, 1)
        XCTAssertEqual(replacementSpaceDescriptors.count, 1)
    }

    func testUpdateTransitionKeepsTheCandidateSpaceBoundAndCommitsOnce() async throws {
        let store = BrowserStore(
            session: .preview,
            persistence: InMemoryBrowserSessionPersistence(),
            credentialVault: InMemoryCredentialVault()
        )
        let space = try XCTUnwrap(store.session.spaces.first)
        let url = try XCTUnwrap(URL(string: "https://accounts.crest.test/login"))
        let origin = try XCTUnwrap(CredentialOrigin(url: url))
        _ = try await store.saveCredential(
            username: "person@example.com",
            password: "old-secret",
            for: url,
            in: space.id
        )
        let candidate = BrowserCredentialSaveCandidate(
            id: UUID(),
            origin: origin,
            topLevelOrigin: origin,
            username: "person@example.com",
            password: "new-secret",
            passwordKind: .current,
            isCrossOriginFrame: false,
            submittedAt: Date(timeIntervalSince1970: 3_000)
        )
        let model = BrowserCredentialSavePromptModel()

        await model.prepare(
            candidate: candidate,
            in: space.id,
            browser: store,
            now: candidate.submittedAt
        )
        XCTAssertEqual(model.phase, .update)
        XCTAssertEqual(model.confirmationAction, .update)

        await model.commit(
            candidate: candidate,
            in: space.id,
            browser: store,
            now: candidate.submittedAt
        )
        XCTAssertEqual(model.phase, .saved(.updated))

        let descriptors = try await store.savedCredentialDescriptors(in: space.id)
        XCTAssertEqual(descriptors.count, 1)
        let credential = try await store.credential(
            id: try XCTUnwrap(descriptors.first?.id),
            in: space.id
        )
        XCTAssertEqual(credential?.password, "new-secret")
    }

    private func localized(
        _ resource: LocalizedStringResource,
        localeIdentifier: String
    ) -> String {
        var localizedResource = resource
        localizedResource.locale = Locale(identifier: localeIdentifier)
        return String(localized: localizedResource)
    }

    private actor SystemPasswordOfferSuspension {
        private var isResumed = false
        private var continuation: CheckedContinuation<Void, Never>?

        func wait() async {
            guard !isResumed else { return }
            await withCheckedContinuation { continuation in
                if isResumed {
                    continuation.resume()
                } else {
                    self.continuation = continuation
                }
            }
        }

        func resume() {
            isResumed = true
            continuation?.resume()
            continuation = nil
        }
    }
}
