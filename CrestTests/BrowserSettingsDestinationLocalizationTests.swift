import XCTest
@testable import Crest

final class BrowserSettingsDestinationLocalizationTests: XCTestCase {
    // MARK: - Search

    func testSearchFindsEachDestinationByItsOwnTitle() {
        let locale = Locale(identifier: "en")

        for destination in BrowserSettingsDestination.platformCases {
            let title = localized(destination.title, locale: locale)
            XCTAssertTrue(
                matches(title, locale: locale).contains(destination),
                "\(destination.rawValue) must answer to its own title"
            )
            XCTAssertTrue(
                matches(title.uppercased(), locale: locale).contains(destination),
                "\(destination.rawValue) must match case-insensitively"
            )
            XCTAssertTrue(
                matches(title.lowercased(), locale: locale).contains(destination),
                "\(destination.rawValue) must match case-insensitively"
            )
        }
    }

    func testSearchTermsKeepBothPlatformsVocabulary() {
        XCTAssertEqual(matches("transparency"), [.general])
        XCTAssertEqual(matches("keyboard"), [.shortcuts])
        XCTAssertEqual(matches("passkeys"), [.passwords])
        XCTAssertEqual(matches("cookies"), [.privacy])
        XCTAssertEqual(matches("isolation"), [.spaces])

        XCTAssertEqual(matches("interface"), [.general])
        XCTAssertEqual(matches("synchronization"), [.passwords])
        XCTAssertEqual(matches("independence"), [.spaces])
        XCTAssertEqual(matches("archive"), [.spaces])

        XCTAssertTrue(matches("permissions").contains(.privacy))
    }

    func testSearchMatchesMultiWordQueriesAndIgnoresCase() {
        XCTAssertEqual(matches("Quick Window"), [.links])
        XCTAssertEqual(matches("quick window"), [.links])
        XCTAssertEqual(matches("QUICK WINDOW"), [.links])
    }

    func testArabicSearchUsesLocalizedTitlesSubtitlesAndKeywords() {
        let arabic = Locale(identifier: "ar")
        let keywordQueries: [BrowserSettingsDestination: String] = [
            .general: "الشفافية",
            .links: "التطبيقات الخارجية",
            .shortcuts: "إعادة التعيين",
            .spaces: "الاستقلالية",
            .sync: "التشخيص",
            .privacy: "ملفات تعريف الارتباط",
            .passwords: "مفاتيح المرور",
            .extensions: "التخزين",
            .advanced: "النسخ الاحتياطي",
        ]

        XCTAssertEqual(matches("الخصوصية", locale: arabic), [.privacy])
        XCTAssertEqual(matches("التعبئة التلقائية", locale: arabic), [.passwords])
        for (destination, query) in keywordQueries {
            XCTAssertEqual(
                matches(query, locale: arabic),
                [destination],
                "\(destination.rawValue) needs localized search vocabulary"
            )
        }
    }

    // MARK: - Deferred localization

    func testPresentationMetadataRemainsDeferredUntilRender() {
        let resources: [LocalizedStringResource] =
            BrowserSettingsDestination.allCases.flatMap { destination in
                [
                    destination.title,
                    destination.navigationTitle,
                    destination.subtitle,
                    destination.searchTerms,
                ]
            }

        XCTAssertEqual(
            resources.count,
            BrowserSettingsDestination.allCases.count * 4
        )
    }

    func testEveryDestinationMetadataResolvesInEnglishAndArabic() {
        let expectedEnglish: [
            BrowserSettingsDestination: (
                title: String,
                navigationTitle: String,
                subtitle: String
            )
        ] = [
            .general: ("General", "General", "Browsing and interface"),
            .links: ("Links", "Links", "Quick Window and Peek"),
            .shortcuts: ("Shortcuts", "Shortcuts", "Keyboard commands"),
            .spaces: ("Spaces", "Spaces", "Profiles and appearance"),
            .sync: ("Sync", "Sync", "iCloud setup and status"),
            .privacy: (
                "Privacy & Permissions",
                "Privacy",
                "Site access and data"
            ),
            .passwords: (
                "Passwords",
                "Passwords",
                "Credentials and autofill"
            ),
            .extensions: (
                "Extensions",
                "Extensions",
                "Space-specific add-ons"
            ),
            .advanced: (
                "Advanced",
                "Advanced",
                "Import, export, and runtime"
            ),
        ]
        let expectedArabic: [
            BrowserSettingsDestination: (
                title: String,
                navigationTitle: String,
                subtitle: String
            )
        ] = [
            .general: ("عام", "عام", "التصفح والواجهة"),
            .links: ("الروابط", "الروابط", "النافذة السريعة وPeek"),
            .shortcuts: (
                "الاختصارات",
                "الاختصارات",
                "أوامر لوحة المفاتيح"
            ),
            .spaces: ("المساحات", "المساحات", "الملفات الشخصية والمظهر"),
            .sync: ("المزامنة", "المزامنة", "إعداد iCloud وحالته"),
            .privacy: (
                "الخصوصية والأذونات",
                "الخصوصية",
                "الوصول إلى المواقع والبيانات"
            ),
            .passwords: (
                "كلمات المرور",
                "كلمات المرور",
                "بيانات الاعتماد والتعبئة التلقائية"
            ),
            .extensions: (
                "الإضافات",
                "الإضافات",
                "إضافات خاصة بكل مساحة"
            ),
            .advanced: (
                "متقدم",
                "متقدم",
                "الاستيراد والتصدير ووقت التشغيل"
            ),
        ]

        assertMetadata(expectedEnglish, locale: Locale(identifier: "en"))
        assertMetadata(expectedArabic, locale: Locale(identifier: "ar"))
    }

    func testEveryDestinationCarriesCompleteLocalizedMetadata() {
        let locale = Locale(identifier: "en")

        for destination in BrowserSettingsDestination.allCases {
            XCTAssertFalse(
                localized(destination.title, locale: locale).isEmpty,
                "\(destination.rawValue) needs a title"
            )
            XCTAssertFalse(
                localized(destination.navigationTitle, locale: locale).isEmpty,
                "\(destination.rawValue) needs a navigation title"
            )
            XCTAssertFalse(
                localized(destination.subtitle, locale: locale).isEmpty,
                "\(destination.rawValue) needs a subtitle"
            )
            XCTAssertFalse(
                destination.symbol.isEmpty,
                "\(destination.rawValue) needs a symbol"
            )
            XCTAssertFalse(
                localized(destination.searchTerms, locale: locale).isEmpty,
                "\(destination.rawValue) needs search terms"
            )
        }
    }

    func testNavigationTitleShortensOnlyPrivacy() {
        let locale = Locale(identifier: "en")

        XCTAssertEqual(
            localized(BrowserSettingsDestination.privacy.title, locale: locale),
            "Privacy & Permissions"
        )
        XCTAssertEqual(
            localized(
                BrowserSettingsDestination.privacy.navigationTitle,
                locale: locale
            ),
            "Privacy"
        )

        for destination in BrowserSettingsDestination.allCases
        where destination != .privacy {
            XCTAssertEqual(
                localized(destination.navigationTitle, locale: locale),
                localized(destination.title, locale: locale),
                "\(destination.rawValue) should not shorten its title"
            )
        }
    }

    // MARK: - Helpers

    private func matches(
        _ query: String,
        locale: Locale = Locale(identifier: "en")
    ) -> [BrowserSettingsDestination] {
        BrowserSettingsDestination.platformCases.filter {
            $0.matchesSearchQuery(query, locale: locale)
        }
    }

    private func assertMetadata(
        _ expected: [
            BrowserSettingsDestination: (
                title: String,
                navigationTitle: String,
                subtitle: String
            )
        ],
        locale: Locale,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for destination in BrowserSettingsDestination.allCases {
            guard let metadata = expected[destination] else {
                XCTFail(
                    "Missing expected metadata for \(destination.rawValue)",
                    file: file,
                    line: line
                )
                continue
            }
            XCTAssertEqual(
                localized(destination.title, locale: locale),
                metadata.title,
                file: file,
                line: line
            )
            XCTAssertEqual(
                localized(destination.navigationTitle, locale: locale),
                metadata.navigationTitle,
                file: file,
                line: line
            )
            XCTAssertEqual(
                localized(destination.subtitle, locale: locale),
                metadata.subtitle,
                file: file,
                line: line
            )
        }
    }

    private func localized(
        _ resource: LocalizedStringResource,
        locale: Locale
    ) -> String {
        var localizedResource = resource
        localizedResource.locale = locale
        return String(localized: localizedResource)
    }
}
