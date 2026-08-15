import XCTest

@testable import Crest

final class BrowserOnboardingLocalizationTests: XCTestCase {
    func testArabicPasswordCountUsesEveryPluralCategory() {
        let expected = [
            0: "لا كلمات سر",
            1: "كلمة سر واحدة",
            2: "كلمتا سر",
            3: "3 كلمات سر",
            11: "11 كلمة سر",
            100: "100 كلمة سر",
        ]

        for (count, value) in expected {
            XCTAssertEqual(
                localized(
                    BrowserOnboardingSummary.passwordCount(count),
                    locale: Locale(identifier: "ar")
                ),
                value,
                "Arabic plural category for \(count)"
            )
        }
    }

    func testWholePhraseSummariesPluralizeEveryIndependentCountInArabic() {
        XCTAssertEqual(
            localized(
                BrowserOnboardingSummary.review(
                    tabCount: 2,
                    passwordCount: 3,
                    overflowTabCount: 11
                ),
                locale: Locale(identifier: "ar")
            ),
            "تم تحديد علامتي تبويب · 3 كلمات سر · ستُنقل 11 علامة تبويب مثبّتة إلى مجلد محفوظ"
        )
        XCTAssertEqual(
            localized(
                BrowserOnboardingSummary.completedManualSetup(
                    newSpaceCount: 2,
                    addedTabCount: 3
                ),
                locale: Locale(identifier: "ar")
            ),
            "تم إنشاء مساحتين وتمت إضافة 3 علامات تبويب."
        )
        XCTAssertEqual(
            localized(
                BrowserOnboardingSummary.completedImport(
                    tabCount: 2,
                    passwordCount: 3,
                    spaceCount: 11
                ),
                locale: Locale(identifier: "ar")
            ),
            "تم استيراد علامتي تبويب تمت مراجعتهما و3 كلمات سر إلى 11 مساحة."
        )
        XCTAssertEqual(
            localized(
                BrowserOnboardingSummary.completedImport(
                    tabCount: 1,
                    passwordCount: 2,
                    spaceCount: 2
                ),
                locale: Locale(identifier: "ar")
            ),
            "تم استيراد علامة تبويب واحدة تمت مراجعتها وكلمتي سر إلى مساحتين."
        )
        XCTAssertEqual(
            localized(
                BrowserOnboardingSummary.completedImport(
                    tabCount: 0,
                    passwordCount: 0,
                    spaceCount: 1
                ),
                locale: Locale(identifier: "ar")
            ),
            "تم استيراد صفر من علامات التبويب التي تمت مراجعتها إلى مساحة واحدة."
        )
        XCTAssertEqual(
            localized(
                BrowserOnboardingSummary.completedImport(
                    tabCount: 0,
                    passwordCount: 2,
                    spaceCount: 1
                ),
                locale: Locale(identifier: "ar")
            ),
            "تم استيراد صفر من علامات التبويب التي تمت مراجعتها وكلمتي سر إلى مساحة واحدة."
        )
    }

    func testKnownFailuresStayDeferredWhileExternalErrorsRemainVerbatim() {
        XCTAssertEqual(
            localizedMessage(
                BrowserOnboardingFailure.sourceUnavailable.message,
                locale: Locale(identifier: "ar")
            ),
            "لم يعد ذلك المتصفح متاحًا على هذا الـ Mac."
        )
        XCTAssertEqual(
            localizedMessage(
                BrowserOnboardingFailure.dataDirectory(.chrome).message,
                locale: Locale(identifier: "ar")
            ),
            "تعذّر على Crest قراءة بيانات \u{2068}Chrome\u{2069} هناك. جرّب «السماح بالوصول» مرة أخرى، أو اختر مجلد بيانات \u{2068}Chrome\u{2069} إذا تم نقله."
        )
        XCTAssertEqual(
            localizedMessage(
                BrowserOnboardingFailure.read("Browser supplied error").message,
                locale: Locale(identifier: "ar")
            ),
            "Browser supplied error"
        )
    }

    func testCatalogOwnsWholePhrasesAndAllArabicPluralForms() throws {
        let strings = try XCTUnwrap(sourceCatalog()["strings"] as? [String: Any])
        let expectedSubstitutions = [
            "%lld tabs selected · %lld passwords": ["tabs", "passwords"],
            "%lld tabs selected · %lld pinned tabs move to a saved folder": [
                "tabs", "overflow",
            ],
            "%lld tabs selected · %lld passwords · %lld pinned tabs move to a saved folder": [
                "tabs", "passwords", "overflow",
            ],
            "Created %lld Spaces and added %lld tabs.": ["spaces", "tabs"],
            "Imported %lld reviewed tabs across %lld Spaces.": ["tabs", "spaces"],
            "Imported %lld reviewed tabs and %lld passwords across %lld Spaces.": [
                "tabs", "passwords", "spaces",
            ],
        ]

        for (key, expectedNames) in expectedSubstitutions {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], key)
            let localizations = try XCTUnwrap(
                entry["localizations"] as? [String: Any],
                key
            )
            for language in ["en", "ar"] {
                let localization = try XCTUnwrap(
                    localizations[language] as? [String: Any],
                    "\(key) [\(language)]"
                )
                let substitutions = try XCTUnwrap(
                    localization["substitutions"] as? [String: Any],
                    "\(key) [\(language)]"
                )
                XCTAssertEqual(
                    Set(substitutions.keys),
                    Set(expectedNames),
                    "\(key) [\(language)]"
                )
                let stringUnit = try XCTUnwrap(
                    localization["stringUnit"] as? [String: Any],
                    "\(key) [\(language)]"
                )
                XCTAssertTrue(
                    (stringUnit["value"] as? String)?.contains("%#@") == true,
                    "\(key) must remain one catalog-controlled phrase"
                )
            }

            let arabic = try XCTUnwrap(
                localizations["ar"] as? [String: Any],
                key
            )
            let substitutions = try XCTUnwrap(
                arabic["substitutions"] as? [String: Any],
                key
            )
            for name in expectedNames {
                let substitution = try XCTUnwrap(
                    substitutions[name] as? [String: Any],
                    "\(key) [\(name)]"
                )
                let variations = try XCTUnwrap(
                    substitution["variations"] as? [String: Any],
                    "\(key) [\(name)]"
                )
                let plurals = try XCTUnwrap(
                    variations["plural"] as? [String: Any],
                    "\(key) [\(name)]"
                )
                XCTAssertEqual(
                    Set(plurals.keys),
                    ["zero", "one", "two", "few", "many", "other"],
                    "\(key) [\(name)]"
                )
            }
        }
    }

    private func localized(
        _ resource: LocalizedStringResource,
        locale: Locale
    ) -> String {
        var resource = resource
        resource.locale = locale
        return String(localized: resource)
    }

    private func localizedMessage(
        _ message: BrowserOnboardingFailureText,
        locale: Locale
    ) -> String {
        switch message {
        case .localized(let resource):
            localized(resource, locale: locale)
        case .verbatim(let text):
            text
        }
    }

    private func sourceCatalog() throws -> [String: Any] {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "CrestShared/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }
}
