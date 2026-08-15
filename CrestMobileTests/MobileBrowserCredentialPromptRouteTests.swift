import Foundation
import XCTest

@testable import CrestMobile

final class MobileBrowserCredentialPromptRouteTests: XCTestCase {
    func testMobileWriteThroughRouteKeepsCrestCommitBeforeSystemPasswords() throws {
        let saveRoute = BrowserCredentialPromptRoute(
            phase: .create,
            systemPasswordOfferPhase: .notRequested,
            offersSystemPasswords: true
        )
        let offeringRoute = BrowserCredentialPromptRoute(
            phase: .saved(.created),
            systemPasswordOfferPhase: .offering,
            offersSystemPasswords: true
        )
        let retryRoute = BrowserCredentialPromptRoute(
            phase: .saved(.created),
            systemPasswordOfferPhase: .failed,
            offersSystemPasswords: true
        )

        XCTAssertEqual(saveRoute.primaryAction, .commit(.create))
        XCTAssertEqual(offeringRoute.busyActivity, .openingSystemPasswords)
        XCTAssertNil(offeringRoute.primaryAction)
        XCTAssertEqual(retryRoute.primaryAction, .retrySystemPasswords)
        XCTAssertEqual(retryRoute.dismissAction, .done)
    }

    func testMobileSystemPasswordsRetryPresentationResolvesExactlyInEnglishAndArabic() throws {
        let route = BrowserCredentialPromptRoute(
            phase: .saved(.created),
            systemPasswordOfferPhase: .failed,
            offersSystemPasswords: true
        )
        let destination = route.destinationMetadata(
            spaceName: "Work",
            syncsWithICloud: false,
            presentation: .combinedStatus
        )
        let isolatedWork = "\u{2068}Work\u{2069}"
        let expectations: [(resource: LocalizedStringResource, english: String, arabic: String)] = [
            (route.title(spaceName: "Work"), "Saved in Work", "تم الحفظ في \(isolatedWork)"),
            (route.dismissActionTitle, "Done", "تم"),
            (
                try XCTUnwrap(route.primaryActionTitle(spaceName: "Work")),
                "Try Passwords Again",
                "إعادة المحاولة مع «كلمات السر»"
            ),
            (
                try XCTUnwrap(route.errorMessage(spaceName: "Work")),
                "Saved in Work. The Passwords offer wasn’t completed.",
                "تم الحفظ في \(isolatedWork). لم يكتمل عرض النسخة على «كلمات السر»."
            ),
            (
                destination.detail,
                "Crest saves in Work first; Passwords asks separately",
                "يحفظ Crest في \(isolatedWork) أولاً؛ ثم تطلب «كلمات السر» تأكيدًا منفصلاً"
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

    private func localized(
        _ resource: LocalizedStringResource,
        localeIdentifier: String
    ) -> String {
        var localizedResource = resource
        localizedResource.locale = Locale(identifier: localeIdentifier)
        return String(localized: localizedResource)
    }
}
