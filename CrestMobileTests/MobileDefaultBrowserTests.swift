import XCTest

@testable import CrestMobile

@MainActor
final class MobileDefaultBrowserTests: XCTestCase {
    func testMobileApplicationKeepsTheProductionCrestBundleIdentityByDefault() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.pauldavis.crest")
    }

    func testMobileApplicationBundlesTheArabicExtendedSurface() throws {
        let arabic = try localizedStrings(in: .main, localization: "ar")

        XCTAssertEqual(arabic["Export Browser Data…"], "تصدير بيانات المتصفح…")
        XCTAssertEqual(arabic["No Results"], "لا توجد نتائج")
        XCTAssertEqual(arabic["Unavailable in Crest"], "غير متاح في Crest")
        XCTAssertEqual(arabic["Default Space"], "المساحة الافتراضية")
        XCTAssertEqual(arabic["Private Space"], "مساحة خاصة")
        XCTAssertEqual(arabic["Unlock Space"], "فتح المساحة")
        XCTAssertEqual(arabic["Choose Emoji Icon"], "اختر رمزًا تعبيريًا")
        XCTAssertEqual(arabic["Delete Tab"], "حذف علامة التبويب")
        XCTAssertEqual(arabic["Hide Toolbar"], "إخفاء شريط الأدوات")
        XCTAssertEqual(arabic["Pull New Icon"], "جلب أيقونة جديدة")
        XCTAssertEqual(arabic["Clear Icon"], "مسح الأيقونة")
        XCTAssertEqual(arabic["Show Toolbar"], "إظهار شريط الأدوات")
        XCTAssertEqual(arabic["Edit Tab"], "تحرير علامة التبويب")
        XCTAssertEqual(arabic["Rename Tab…"], "إعادة تسمية علامة التبويب…")
        XCTAssertEqual(arabic["Rename Tab"], "إعادة تسمية علامة التبويب")
        XCTAssertEqual(arabic["Tab Name"], "اسم علامة التبويب")
        XCTAssertEqual(arabic["Appearance"], "المظهر")
        XCTAssertEqual(arabic["Gradient rotation"], "تدوير التدرج")
        XCTAssertEqual(arabic["Texture"], "النسيج")
        // The banner forge's vocabulary is hand-kept: its labels are built from
        // runtime design-token names, so the compiler cannot extract them and
        // nothing but this catches a term that was never translated.
        XCTAssertEqual(arabic["Pattern"], "النمط")
        XCTAssertEqual(arabic["Mark"], "العلامة")
        XCTAssertEqual(arabic["Charge"], "الرمز")
        XCTAssertEqual(arabic["Quartered"], "أرباع")
        XCTAssertEqual(arabic["Bordure"], "إطار محيط")
        XCTAssertEqual(arabic["Rising Sun"], "الشمس الشارقة")
        XCTAssertEqual(arabic["Crown"], "التاج")
        XCTAssertEqual(arabic["Banners"], "الرايات")
        XCTAssertEqual(arabic["Charge color"], "لون الرمز")
        XCTAssertEqual(
            arabic["Replace with Current URL"],
            "استبدال بعنوان URL الحالي"
        )
        XCTAssertEqual(
            arabic["Return to Saved URL"],
            "العودة إلى عنوان URL المحفوظ"
        )
    }

    func testMobileApplicationBundlesTheArabicCoreBrowserCatalog() throws {
        let arabic = try localizedStrings(in: .main, localization: "ar")

        XCTAssertEqual(arabic["Start Page"], "صفحة البداية")
        XCTAssertEqual(arabic["Search or Enter URL…"], "ابحث أو أدخل عنوان URL…")
        XCTAssertEqual(arabic["Private Browsing"], "التصفح الخاص")
        XCTAssertEqual(arabic["New Tab"], "علامة تبويب جديدة")
        XCTAssertEqual(arabic["Settings"], "الإعدادات")
        XCTAssertEqual(arabic["Archive"], "الأرشيف")
        XCTAssertEqual(arabic["Downloads"], "التنزيلات")
        XCTAssertEqual(arabic["Tabs"], "علامات التبويب")
    }

    func testMobileApplicationBundlesTheArabicCommandSurface() throws {
        let arabic = try localizedStrings(in: .main, localization: "ar")

        XCTAssertEqual(arabic["Back"], "رجوع")
        XCTAssertEqual(arabic["Find in Page"], "بحث في الصفحة")
        XCTAssertEqual(arabic["Page Actions"], "إجراءات الصفحة")
        XCTAssertEqual(arabic["Reload from Origin"], "إعادة التحميل من المصدر")
        XCTAssertEqual(arabic["Stop Loading"], "إيقاف التحميل")
        XCTAssertEqual(arabic["Next Space"], "المساحة التالية")
        XCTAssertEqual(arabic["Duplicate Tab"], "تكرار علامة التبويب")
        XCTAssertEqual(arabic["Share & Export…"], "مشاركة وتصدير…")
        XCTAssertEqual(arabic["Export Web Archive…"], "تصدير أرشيف الويب…")
    }

    func testMobileApplicationBundlesTheArabicSettingsAndPrivacySurface() throws {
        let arabic = try localizedStrings(in: .main, localization: "ar")

        XCTAssertEqual(arabic["Browser Settings"], "إعدادات المتصفح")
        XCTAssertEqual(arabic["Default browser"], "المتصفح الافتراضي")
        XCTAssertEqual(arabic["Content Blocking"], "حظر المحتوى")
        XCTAssertEqual(arabic["Website Notifications"], "إشعارات مواقع الويب")
        XCTAssertEqual(arabic["Space isolation"], "عزل المساحات")
        XCTAssertEqual(arabic["No Saved Permissions"], "لا توجد أذونات محفوظة")
        XCTAssertEqual(arabic["No Archived Tabs"], "لا توجد علامات تبويب مؤرشفة")
        XCTAssertEqual(arabic["No Downloads"], "لا توجد تنزيلات")
    }

    func testMobileApplicationBundlesTheArabicCredentialAndPrivateSurface() throws {
        let arabic = try localizedStrings(in: .main, localization: "ar")

        XCTAssertEqual(arabic["Crest Passwords"], "كلمات مرور Crest")
        XCTAssertEqual(arabic["Password hidden"], "كلمة المرور مخفية")
        XCTAssertEqual(arabic["Password visible"], "كلمة المرور ظاهرة")
        XCTAssertEqual(arabic["System Passkeys"], "مفاتيح مرور النظام")
        XCTAssertEqual(
            arabic["Removing private browser data…"],
            "جارٍ إزالة بيانات التصفح الخاص…"
        )
        XCTAssertEqual(
            arabic["Crest does not save this session or use Crest Passwords. Website data stays in memory only."],
            "لا يحفظ Crest هذه الجلسة ولا يستخدم كلمات مرور Crest. تبقى بيانات مواقع الويب في الذاكرة فقط."
        )
        XCTAssertEqual(
            arabic[
                "Passkeys belong to the system account and may appear in any Space. The page’s cookies and sign-in session remain in the active Space."
            ],
            "تنتمي مفاتيح المرور إلى حساب النظام وقد تظهر في أي مساحة. وتظل ملفات تعريف الارتباط وجلسة تسجيل الدخول الخاصة بالصفحة في المساحة النشطة."
        )
    }

    func testMobileApplicationBundlesTheArabicTabAndTransientSurface() throws {
        let arabic = try localizedStrings(in: .main, localization: "ar")

        XCTAssertEqual(arabic["Current tabs"], "علامات التبويب الحالية")
        XCTAssertEqual(arabic["Pinned tabs"], "علامات التبويب المثبتة")
        XCTAssertEqual(arabic["Saved tabs"], "علامات التبويب المحفوظة")
        XCTAssertEqual(arabic["Close Peek"], "إغلاق Peek")
        XCTAssertEqual(arabic["Quick Window"], "النافذة السريعة")
        XCTAssertEqual(arabic["Page Stopped"], "توقفت الصفحة")
        XCTAssertEqual(arabic["Tab Unloaded"], "تم إلغاء تحميل علامة التبويب")
        XCTAssertEqual(arabic["Folder Name"], "اسم المجلد")
        XCTAssertEqual(
            arabic["Crest released this temporary page to reduce memory use."],
            "حرر Crest هذه الصفحة المؤقتة لتقليل استخدام الذاكرة."
        )
    }

    func testMobileApplicationBundlesTheArabicSystemPasswordSurface() throws {
        let arabic = try localizedStrings(in: .main, localization: "ar")

        XCTAssertEqual(
            arabic["Save & Offer to Passwords"],
            "حفظ وعرض نسخة على «كلمات السر»"
        )
        XCTAssertEqual(arabic["Save in %@"], "حفظ في %@")
        XCTAssertEqual(
            arabic["Saved in %@. The Passwords offer wasn’t completed."],
            "تم الحفظ في %@. لم يكتمل عرض النسخة على «كلمات السر»."
        )
        XCTAssertEqual(
            arabic["This option becomes available after Apple approves Crest’s managed browser capability."],
            "يصبح هذا الخيار متاحًا بعد موافقة Apple على إمكانية المتصفح المُدارة الخاصة بـ Crest."
        )
        XCTAssertEqual(
            arabic["Try Passwords Again"],
            "إعادة المحاولة مع «كلمات السر»"
        )
        XCTAssertEqual(
            arabic["Update & Offer to Passwords"],
            "تحديث وعرض نسخة على «كلمات السر»"
        )
    }

    func testMobileApplicationBundlesTheMinimalCrestPrivacyManifest() throws {
        let manifestURL = try XCTUnwrap(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy")
        )
        let data = try Data(contentsOf: manifestURL)
        let manifest = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        )

        XCTAssertEqual(
            Set(manifest.keys),
            [
                "NSPrivacyTracking",
                "NSPrivacyCollectedDataTypes",
                "NSPrivacyAccessedAPITypes",
            ])
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertNil(manifest["NSPrivacyTrackingDomains"])
        let collectedDataTypes = try XCTUnwrap(
            manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]]
        )
        XCTAssertTrue(collectedDataTypes.isEmpty)

        let entries = try XCTUnwrap(
            manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]]
        )
        let reasons = try Dictionary(
            uniqueKeysWithValues: entries.map { entry in
                (
                    try XCTUnwrap(entry["NSPrivacyAccessedAPIType"] as? String),
                    try XCTUnwrap(entry["NSPrivacyAccessedAPITypeReasons"] as? [String])
                )
            })
        XCTAssertEqual(
            reasons,
            [
                "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"]
            ])
    }

    func testPasskeyBuildManifestIsEnabledAfterTheManagedEntitlementIsProvisioned() {
        XCTAssertEqual(
            Bundle.main.object(
                forInfoDictionaryKey: "CrestBrowserPasskeyManagedCapability"
            ) as? Bool,
            true
        )
    }

    func testSystemPasswordWriteThroughManifestIsEnabledAfterBrowserApproval() {
        XCTAssertEqual(
            Bundle.main.object(
                forInfoDictionaryKey: "CrestSystemPasswordWriteThroughManagedCapability"
            ) as? Bool,
            true
        )
        XCTAssertEqual(
            BrowserSystemPasswordWriteThroughSystem.availability(
                for: BrowserLaunchEnvironment(
                    values: [:],
                    isXCTestRuntime: false
                )
            ),
            .available
        )
    }

    func testIsolatedLaunchRejectsSystemPasswordWriteThroughBeforePresentation()
        async throws
    {
        let origin = try XCTUnwrap(
            CredentialOrigin(
                url: try XCTUnwrap(URL(string: "https://accounts.example.com"))
            )
        )
        let candidate = BrowserCredentialSaveCandidate(
            id: UUID(),
            origin: origin,
            topLevelOrigin: origin,
            username: "person@example.com",
            password: "secret",
            passwordKind: .current,
            isCrossOriginFrame: false,
            submittedAt: .now
        )

        do {
            try await BrowserSystemPasswordWriteThroughSystem.offer(
                candidate: candidate,
                title: "Isolated",
                anchor: nil
            )
            XCTFail("An isolated launch must not reach ASCredentialDataManager.")
        } catch {
            XCTAssertEqual(
                error as? BrowserSystemPasswordWriteThroughError,
                .unavailable
            )
        }
    }

    func testMobileApplicationRegistersBothWebURLSchemes() throws {
        let urlTypes = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes")
                as? [[String: Any]]
        )
        let schemes = Set(
            urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        )

        XCTAssertTrue(schemes.contains("http"))
        XCTAssertTrue(schemes.contains("https"))
    }

    func testMobileApplicationSupportsIndependentNativeWindowScenes() throws {
        let sceneManifest = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest")
                as? [String: Any]
        )

        XCTAssertEqual(
            sceneManifest["UIApplicationSupportsMultipleScenes"] as? Bool,
            true
        )
    }

    func testDefaultBrowserStatusIsNeverPolledByControllerInitialization() {
        var statusCheckCount = 0
        let controller = BrowserDefaultBrowserController(
            requestStyle: .systemSettings,
            statusCheck: {
                statusCheckCount += 1
                return false
            },
            defaultRequest: {},
            settingsOpener: {}
        )

        XCTAssertEqual(statusCheckCount, 0)
        XCTAssertEqual(controller.status, .unknown)

        controller.refreshStatus()

        XCTAssertEqual(statusCheckCount, 1)
        XCTAssertEqual(controller.status, .notDefault)
    }

    func testApprovedDefaultBrowserFlowOpensSystemSettingsWithoutImplicitStatusCheck() {
        var statusCheckCount = 0
        var settingsOpenCount = 0
        let controller = BrowserDefaultBrowserController(
            requestStyle: .systemSettings,
            statusCheck: {
                statusCheckCount += 1
                return false
            },
            defaultRequest: {},
            settingsOpener: { settingsOpenCount += 1 }
        )

        XCTAssertEqual(controller.requestStyle, .systemSettings)
        controller.openSystemSettings()

        XCTAssertEqual(settingsOpenCount, 1)
        XCTAssertEqual(statusCheckCount, 0)
        XCTAssertEqual(controller.status, .unknown)
    }

    func testMobileExternalURLPolicyRejectsNonWebSchemes() throws {
        XCTAssertTrue(
            BrowserExternalURLPolicy.accepts(
                try XCTUnwrap(URL(string: "https://example.com"))
            )
        )
        XCTAssertFalse(
            BrowserExternalURLPolicy.accepts(
                try XCTUnwrap(URL(string: "javascript:alert(1)"))
            )
        )
        XCTAssertFalse(
            BrowserExternalURLPolicy.accepts(
                try XCTUnwrap(URL(string: "data:text/plain,hello"))
            )
        )
    }

    func testMobileOutboundSchemesLeaveWebKitOrAreBlocked() throws {
        XCTAssertEqual(
            BrowserExternalSchemePolicy.disposition(
                for: try XCTUnwrap(URL(string: "https://example.com"))
            ),
            .webKit
        )
        XCTAssertEqual(
            BrowserExternalSchemePolicy.disposition(
                for: try XCTUnwrap(URL(string: "data:text/plain,hello"))
            ),
            .webKit
        )
        XCTAssertEqual(
            BrowserExternalSchemePolicy.disposition(
                for: try XCTUnwrap(URL(string: "tel:+15555550100"))
            ),
            .handOff
        )
        XCTAssertEqual(
            BrowserExternalSchemePolicy.disposition(
                for: try XCTUnwrap(URL(string: "sms:+15555550100"))
            ),
            .handOff
        )
        XCTAssertEqual(
            BrowserExternalSchemePolicy.disposition(
                for: try XCTUnwrap(URL(string: "javascript:alert(1)"))
            ),
            .blocked
        )
        XCTAssertEqual(
            BrowserExternalSchemePolicy.disposition(
                for: try XCTUnwrap(URL(string: "file:///tmp/index.html"))
            ),
            .blocked
        )
    }

    func testMobileScriptedExternalSchemePromptsWithoutARememberedApproval() {
        XCTAssertEqual(
            BrowserExternalSchemeConsent.resolve(trigger: .scripted, decision: .ask),
            .prompt
        )
        XCTAssertEqual(
            BrowserExternalSchemeConsent.resolve(
                trigger: .scripted,
                decision: .grantPersistently
            ),
            .open
        )
        XCTAssertEqual(
            BrowserExternalSchemeConsent.resolve(
                trigger: .explicitUserNavigation,
                decision: .ask
            ),
            .prompt
        )
    }

    private func localizedStrings(
        in bundle: Bundle,
        localization: String
    ) throws -> [String: String] {
        let url = try XCTUnwrap(
            bundle.url(
                forResource: "Localizable",
                withExtension: "strings",
                subdirectory: nil,
                localization: localization
            )
        )
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: String]
        )
    }
}
