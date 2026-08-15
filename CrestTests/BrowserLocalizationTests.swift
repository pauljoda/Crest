import XCTest
@testable import Crest

final class BrowserLocalizationTests: XCTestCase {
    func testEverySourceCatalogEntryHasArabicLocalization() throws {
        let catalog = try sourceCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let missingArabic = strings.compactMap { key, value -> String? in
            guard !key.isEmpty else {
                return nil
            }
            guard
                let entry = value as? [String: Any],
                let localizations = entry["localizations"] as? [String: Any],
                let arabic = localizations["ar"] as? [String: Any],
                hasCompleteTranslation(arabic)
            else {
                return key
            }
            return nil
        }

        XCTAssertEqual(missingArabic.sorted(), [])
    }

    func testSourceCatalogCoversTheExtractableBrowserSurface() throws {
        let catalog = try sourceCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])

        XCTAssertEqual(catalog["sourceLanguage"] as? String, "en")
        XCTAssertGreaterThanOrEqual(strings.count, 340)
    }

    func testMigrationSurfaceIsExtractableAndTranslatedForArabic() throws {
        let catalog = try sourceCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let extractableKeys = [
            "Bookmarks HTML",
            "Safari",
            "Chrome or Chromium",
            "Firefox",
            "Arc",
            "Safari Session",
            "Chrome or Chromium Session",
            "Firefox Session",
            "Arc Sidebar or Session",
            "Zen Spaces or Session",
            "Imported Bookmarks",
            "Imported from Safari",
            "Imported from Chrome",
            "Imported from Firefox",
            "Imported from Arc",
            "Imported History from Safari",
            "Imported History from Chrome",
            "Imported History from Firefox",
            "Imported History from Arc",
            "Imported Safari Tabs",
            "Imported Chrome Tabs",
            "Imported Firefox Tabs",
            "Imported Arc Tabs",
            "Imported Zen Tabs",
            "Imported Safari Window %lld",
            "Imported Chrome Window %lld",
            "Imported Firefox Window %lld",
            "Imported Arc Space %lld",
            "Imported Zen Space %lld",
            "Reading %@ bookmarks…",
            "Reading %@ history…",
            "Reading %@ tabs…",
            "Imported %lld bookmarks in %lld Spaces from %@.",
            "Imported %lld history entries from %@.",
            "Imported %lld tabs in %lld Spaces from %@.",
            "Import from another browser requires Crest for macOS. Once imported, your Spaces and tabs sync to this device with iCloud.",
            "Exports Spaces, folders, saved and current tabs, Archive, history, and browsing preferences. Passwords, cookies, website storage, permissions, downloads, favicons, and extensions are never included.",
            "Bookmark HTML includes pinned and saved sites only. Imports from standard HTML, Safari, Chrome or Chromium, Firefox, and Arc always create fresh, isolated Crest Spaces.",
            "History import accepts a copied Safari History.db, Chrome or Arc History database, or Firefox places.sqlite. Quit the source browser before copying; Crest imports up to 5,000 recent entries.",
            "Open-tab import accepts a copied Safari session property list, cleartext Chrome or Chromium Session_* file, Firefox recovery.jsonlz4 or sessionstore.jsonlz4, or Arc StorableSidebar.json. Each source window becomes a fresh, isolated Crest Space; profile-encrypted Chromium sessions cannot be imported.",
            "This bookmark file is larger than Crest’s 50 MB import limit.",
            "Crest could not recognize this browser’s bookmark data.",
            "This file does not contain any HTTP or HTTPS bookmarks Crest can import.",
            "This bookmark file exceeds Crest’s folder, depth, tab, or Space limits.",
            "This history database is larger than Crest’s 512 MB import limit.",
            "Crest could not read this history database.",
            "Quit the source browser, copy its history database, and import the copy.",
            "This file does not match the selected browser’s history format.",
            "This database has no HTTP or HTTPS history Crest can import.",
            "This session file is larger than Crest’s 512 MB import limit.",
            "Crest could not recognize this browser’s tab-session data.",
            "This Chromium session is profile-encrypted and cannot be safely imported outside its source browser.",
            "This session has no HTTP or HTTPS tabs Crest can import.",
            "This session exceeds Crest’s tab, window, text, or decompression limits.",
            "This file is larger than Crest’s 50 MB import limit.",
            "This file does not contain valid Crest browser data.",
            "This is not a Crest browser-data file.",
            "This Crest browser-data version (%lld) is not supported.",
            "Crest could not read this file.",
            "Crest supports up to %lld Spaces. Remove a Space before importing this file.",
        ]

        for key in extractableKeys {
            XCTAssertNotNil(strings[key], key)
        }

        let expectedArabic = [
            "Export Bookmarks as HTML…": "تصدير الإشارات المرجعية بتنسيق HTML…",
            "Import Bookmarks…": "استيراد الإشارات المرجعية…",
            "Import History…": "استيراد السجل…",
            "Import Open Tabs…": "استيراد علامات التبويب المفتوحة…",
            "Import from another browser requires Crest for macOS. Once imported, your Spaces and tabs sync to this device with iCloud.": "يتطلب الاستيراد من متصفح آخر تطبيق Crest لنظام macOS. بعد الاستيراد، تتم مزامنة المساحات وعلامات التبويب إلى هذا الجهاز عبر iCloud.",
            "Bookmarks HTML": "إشارات HTML المرجعية",
            "Chrome or Chromium": "Chrome أو Chromium",
            "Safari Session": "جلسة Safari",
            "Arc Sidebar or Session": "شريط Arc الجانبي أو الجلسة",
        ]

        for (key, expectedValue) in expectedArabic {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], key)
            let localizations = try XCTUnwrap(
                entry["localizations"] as? [String: Any],
                key
            )
            let arabic = try XCTUnwrap(localizations["ar"] as? [String: Any], key)
            let stringUnit = try XCTUnwrap(arabic["stringUnit"] as? [String: Any], key)
            XCTAssertEqual(stringUnit["value"] as? String, expectedValue, key)
        }
    }

    func testMigrationSourceTitlesRemainDeferredLocalizedResources() {
        let titles: [LocalizedStringResource] = [
            BrowserBookmarkMigrationSource.htmlBookmarks.title,
            BrowserHistoryMigrationSource.chrome.title,
            BrowserTabMigrationSource.firefox.title,
        ]

        XCTAssertEqual(titles.count, 3)
    }

    func testSystemPasswordWriteThroughSurfaceIsExtractable() throws {
        let catalog = try sourceCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let keys = [
            "After Crest saves in this Space, the system can ask whether to save or update a copy in your preferred password manager.",
            "Crest saves in %@ first; Passwords asks separately",
            "On Mac, WebKit and the system manage Passwords integration directly.",
            "Opening Passwords",
            "Offering a copy to Passwords requires iOS or iPadOS 26.2 or later.",
            "Save & Offer to Passwords",
            "Save in %@",
            "Saved in %@. The Passwords offer wasn’t completed.",
            "Stored only in %@, with Crest iCloud sync",
            "Stored only in the %@ Space",
            "This option becomes available after Apple approves Crest’s managed browser capability.",
            "Try Passwords Again",
            "Update & Offer to Passwords",
            "Update in %@",
        ]

        for key in keys {
            XCTAssertNotNil(strings[key], key)
        }

        let expectedArabic = [
            "After Crest saves in this Space, the system can ask whether to save or update a copy in your preferred password manager.": "بعد أن يحفظ Crest كلمة المرور في هذه المساحة، يمكن للنظام أن يسأل عما إذا كنت تريد حفظ نسخة أو تحديثها في مدير كلمات المرور المفضّل لديك.",
            "Crest saves in %@ first; Passwords asks separately": "يحفظ Crest في %@ أولاً؛ ثم تطلب «كلمات السر» تأكيدًا منفصلاً",
            "On Mac, WebKit and the system manage Passwords integration directly.": "على Mac، يدير WebKit والنظام تكامل «كلمات السر» مباشرةً.",
            "Opening Passwords": "جارٍ فتح «كلمات السر»",
            "Offering a copy to Passwords requires iOS or iPadOS 26.2 or later.": "يتطلب عرض نسخة على «كلمات السر» iOS أو iPadOS 26.2 أو أحدث.",
            "Save & Offer to Passwords": "حفظ وعرض نسخة على «كلمات السر»",
            "Save in %@": "حفظ في %@",
            "Saved in %@. The Passwords offer wasn’t completed.": "تم الحفظ في %@. لم يكتمل عرض النسخة على «كلمات السر».",
            "Stored only in %@, with Crest iCloud sync": "مخزّنة في %@ فقط، مع مزامنة Crest عبر iCloud",
            "Stored only in the %@ Space": "مخزّنة في مساحة %@ فقط",
            "This option becomes available after Apple approves Crest’s managed browser capability.": "يصبح هذا الخيار متاحًا بعد موافقة Apple على إمكانية المتصفح المُدارة الخاصة بـ Crest.",
            "Try Passwords Again": "إعادة المحاولة مع «كلمات السر»",
            "Update & Offer to Passwords": "تحديث وعرض نسخة على «كلمات السر»",
            "Update in %@": "تحديث في %@",
        ]

        for (key, expectedValue) in expectedArabic {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], key)
            let localizations = try XCTUnwrap(
                entry["localizations"] as? [String: Any],
                key
            )
            let arabic = try XCTUnwrap(localizations["ar"] as? [String: Any], key)
            let stringUnit = try XCTUnwrap(arabic["stringUnit"] as? [String: Any], key)
            XCTAssertEqual(stringUnit["value"] as? String, expectedValue, key)
        }
    }

    func testMigrationGeneratedNamesAndErrorsRemainDeferredLocalizedResources() {
        let resources: [LocalizedStringResource] = [
            BrowserBookmarkMigrationSource.safariBookmarks.importedSpaceName,
            BrowserHistoryMigrationSource.firefox.importedSpaceName,
            BrowserTabMigrationSource.arc.importedSpaceName,
            BrowserBookmarkMigrationError.invalidContents.errorDescriptionResource,
            BrowserHistoryMigrationError.databaseBusy.errorDescriptionResource,
            BrowserTabMigrationError.encryptedChromiumSession.errorDescriptionResource,
            BrowserPortableArchiveError.unsupportedSchemaVersion(99)
                .errorDescriptionResource,
        ]

        XCTAssertEqual(resources.count, 7)
    }

    func testMigrationGeneratedNamesAndErrorsResolveInArabic() {
        let arabic = Locale(identifier: "ar")

        XCTAssertEqual(
            localized(
                BrowserBookmarkMigrationSource.safariBookmarks.importedSpaceName,
                locale: arabic
            ),
            "تم الاستيراد من Safari"
        )
        XCTAssertEqual(
            localized(
                BrowserHistoryMigrationSource.firefox.importedSpaceName,
                locale: arabic
            ),
            "تم استيراد السجل من Firefox"
        )
        XCTAssertEqual(
            localized(
                BrowserHistoryMigrationError.databaseBusy.errorDescriptionResource,
                locale: arabic
            ),
            "أغلق المتصفح المصدر، وانسخ قاعدة بيانات السجل، ثم استورد النسخة."
        )
        XCTAssertEqual(
            localized(
                BrowserTabMigrationError.encryptedChromiumSession.errorDescriptionResource,
                locale: arabic
            ),
            "جلسة Chromium هذه مشفرة بالملف الشخصي ولا يمكن استيرادها بأمان خارج متصفحها المصدر."
        )
    }

    @MainActor
    func testDynamicPageActionsRemainDeferredAndResolveInArabic() throws {
        let pages = BrowserPagePool(monitorsMemoryPressure: false)
        let deferredTitle: LocalizedStringResource = pages.readerModeActionTitle
        XCTAssertEqual(
            localized(deferredTitle, locale: Locale(identifier: "ar")),
            "إظهار القارئ"
        )

        let catalog = try sourceCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let expectedArabic = [
            "Show Reader": "إظهار القارئ",
            "Hide Reader": "إخفاء القارئ",
            "Request Desktop Website": "طلب موقع سطح المكتب",
            "Request Mobile Website": "طلب موقع الهاتف المحمول",
            "Turn On Balanced Content Blocking in This Space": "تشغيل حظر المحتوى المتوازن في هذه المساحة",
            "Turn Off Content Blocking in This Space": "إيقاف حظر المحتوى في هذه المساحة",
        ]

        for (key, expectedValue) in expectedArabic {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], key)
            let localizations = try XCTUnwrap(
                entry["localizations"] as? [String: Any],
                key
            )
            let arabic = try XCTUnwrap(localizations["ar"] as? [String: Any], key)
            let stringUnit = try XCTUnwrap(arabic["stringUnit"] as? [String: Any], key)
            XCTAssertEqual(stringUnit["value"] as? String, expectedValue, key)
        }
    }

    func testBrowserCommandSurfaceResolvesInArabic() throws {
        let catalog = try sourceCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let expectedArabic = [
            "Actual Size": "الحجم الفعلي",
            "Back": "رجوع",
            "Clear History": "مسح السجل",
            "Close Private Tabs": "إغلاق علامات التبويب الخاصة",
            "Close Tab": "إغلاق علامة التبويب",
            "Close Window": "إغلاق النافذة",
            "Command Palette": "لوحة الأوامر",
            "Copy Page Link": "نسخ رابط الصفحة",
            "Copy Page Link as Markdown": "نسخ رابط الصفحة بتنسيق Markdown",
            "Duplicate Tab": "تكرار علامة التبويب",
            "Export as PDF…": "تصدير بتنسيق PDF…",
            "Export Web Archive…": "تصدير أرشيف الويب…",
            "Find in Page": "بحث في الصفحة",
            "Forward": "تقدم",
            "Hide Sidebar": "إخفاء الشريط الجانبي",
            "History": "السجل",
            "Leave Private Browsing": "مغادرة التصفح الخاص",
            "New Browser Window": "نافذة متصفح جديدة",
            "New Folder": "مجلد جديد",
            "New Private Window": "نافذة خاصة جديدة",
            "New Quick Window": "نافذة سريعة جديدة",
            "New Space": "مساحة جديدة",
            "Next Space": "المساحة التالية",
            "Next Tab": "علامة التبويب التالية",
            "Open Location": "فتح الموقع",
            "Page Actions": "إجراءات الصفحة",
            "Previous Space": "المساحة السابقة",
            "Previous Tab": "علامة التبويب السابقة",
            "Print…": "طباعة…",
            "Reload": "إعادة تحميل",
            "Reload from Origin": "إعادة التحميل من المصدر",
            "Reopen Closed Tab": "إعادة فتح علامة التبويب المغلقة",
            "Share & Export…": "مشاركة وتصدير…",
            "Share…": "مشاركة…",
            "Show Sidebar": "إظهار الشريط الجانبي",
            "Stop": "إيقاف",
            "Stop Loading": "إيقاف التحميل",
            "Zoom In": "تكبير",
            "Zoom Out": "تصغير",
        ]

        for (key, expectedValue) in expectedArabic {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], key)
            let localizations = try XCTUnwrap(
                entry["localizations"] as? [String: Any],
                key
            )
            let arabic = try XCTUnwrap(localizations["ar"] as? [String: Any], key)
            let stringUnit = try XCTUnwrap(arabic["stringUnit"] as? [String: Any], key)
            XCTAssertEqual(stringUnit["value"] as? String, expectedValue, key)
        }
    }

    func testSettingsPrivacyAndDataManagementSurfaceResolvesInArabic() throws {
        let catalog = try sourceCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let expectedArabic = [
            "Add Space": "إضافة مساحة",
            "Allow": "سماح",
            "Apple does not expose website-notification permission or background Web Push delivery to third-party WKWebView browsers. On iPhone and iPad, notification-capable sites must be added to the Home Screen; on Mac, they must use Safari or an installed web app.": "لا توفر Apple إذن إشعارات مواقع الويب أو تسليم إشعارات Web Push في الخلفية لمتصفحات WKWebView التابعة لجهات خارجية. على iPhone وiPad، يجب إضافة المواقع التي تدعم الإشعارات إلى الشاشة الرئيسية؛ وعلى Mac، يجب استخدام Safari أو تطبيق ويب مثبت.",
            "Archive current tabs": "أرشفة علامات التبويب الحالية",
            "Archive Tab": "أرشفة علامة التبويب",
            "Ask Again": "السؤال مجددًا",
            "Auto-archive": "الأرشفة التلقائية",
            "Balanced uses a native WebKit rule list to stop known third-party advertising and tracking requests. Top-level pages are never blocked, and the choice applies only to this Space.": "يستخدم الوضع المتوازن قائمة قواعد أصلية من WebKit لإيقاف طلبات الإعلانات والتتبع المعروفة التابعة لجهات خارجية. ولا تُحظر الصفحات الرئيسية أبدًا، وينطبق هذا الخيار على هذه المساحة فقط.",
            "Block": "حظر",
            "Browser Settings": "إعدادات المتصفح",
            "Cancel Download": "إلغاء التنزيل",
            "Choices are stored separately for each exact site, port, capability, and Space. Camera and microphone access also require macOS privacy consent.": "تُخزّن الخيارات بشكل منفصل لكل موقع ومنفذ وإمكانية ومساحة بالضبط. ويتطلب الوصول إلى الكاميرا والميكروفون أيضًا موافقة الخصوصية في macOS.",
            "Choose a Space to edit its identity and privacy policy.": "اختر مساحة لتعديل هويتها وسياسة الخصوصية الخاصة بها.",
            "Clear": "مسح",
            "Clear history for %@?": "هل تريد مسح سجل %@؟",
            "Clear Unpinned Tabs": "مسح علامات التبويب غير المثبتة",
            "Content blocking": "حظر المحتوى",
            "Content Blocking": "حظر المحتوى",
            "Default browser": "المتصفح الافتراضي",
            "Delete Space": "حذف المساحة",
            "Delete Space and Data": "حذف المساحة والبيانات",
            "Deleting Space…": "جارٍ حذف المساحة…",
            "Every exact site, port, capability, and Space has its own choice. Camera and microphone access also require device-level privacy consent.": "لكل موقع ومنفذ وإمكانية ومساحة بالضبط خيار مستقل. ويتطلب الوصول إلى الكاميرا والميكروفون أيضًا موافقة الخصوصية على مستوى الجهاز.",
            "Every Space has its own website data, history, tabs, permissions, and Crest Passwords.": "لكل مساحة بيانات مواقع الويب والسجل وعلامات التبويب والأذونات وكلمات مرور Crest الخاصة بها.",
            "Export Download": "تصدير التنزيل",
            "History entries": "إدخالات السجل",
            "History in other Spaces is not affected.": "لن يتأثر السجل في المساحات الأخرى.",
            "History remains private to this Space.": "يظل السجل خاصًا بهذه المساحة.",
            "Make Crest Default Browser": "تعيين Crest متصفحًا افتراضيًا",
            "Makes every site ask again in this Space": "يجعل كل موقع يسأل مجددًا في هذه المساحة",
            "No Archived Tabs": "لا توجد علامات تبويب مؤرشفة",
            "No Downloads": "لا توجد تنزيلات",
            "No History": "لا يوجد سجل",
            "No Saved Permissions": "لا توجد أذونات محفوظة",
            "No Spaces": "لا توجد مساحات",
            "Permissions for": "أذونات لـ",
            "Remove Download": "إزالة التنزيل",
            "Search settings": "البحث في الإعدادات",
            "Search this Space": "البحث في هذه المساحة",
            "Show History": "إظهار السجل",
            "Sites will ask before using protected capabilities, opening pop-ups, or starting automatic downloads in this Space.": "ستطلب المواقع الإذن قبل استخدام الإمكانات المحمية أو فتح النوافذ المنبثقة أو بدء التنزيلات التلقائية في هذه المساحة.",
            "Space Actions": "إجراءات المساحة",
            "Space actions": "إجراءات المساحة",
            "Space isolation": "عزل المساحات",
            "Updating default browser": "جارٍ تحديث المتصفح الافتراضي",
            "Website": "موقع الويب",
            "Website Notifications": "إشعارات مواقع الويب",
            "Website notifications": "إشعارات مواقع الويب",
        ]

        for (key, expectedValue) in expectedArabic {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], key)
            let localizations = try XCTUnwrap(
                entry["localizations"] as? [String: Any],
                key
            )
            let arabic = try XCTUnwrap(localizations["ar"] as? [String: Any], key)
            let stringUnit = try XCTUnwrap(arabic["stringUnit"] as? [String: Any], key)
            XCTAssertEqual(stringUnit["value"] as? String, expectedValue, key)
        }
    }

    func testPasswordsPasskeysAndPrivateBrowsingSurfaceResolvesInArabic() throws {
        let catalog = try sourceCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let expectedArabic = [
            "Account": "الحساب",
            "Allow Crest to Use Passkeys…": "السماح لـ Crest باستخدام مفاتيح المرور…",
            "Also offer saves to Passwords": "عرض الحفظ في «كلمات السر» أيضًا",
            "Authenticate to copy the Crest password for %@.": "قم بالمصادقة لنسخ كلمة مرور Crest لـ %@.",
            "Authenticate to export passwords from %@.": "قم بالمصادقة لتصدير كلمات المرور من %@.",
            "Authenticate to reveal the Crest password for %@.": "قم بالمصادقة لإظهار كلمة مرور Crest لـ %@.",
            "Authenticate to view this Crest password.": "قم بالمصادقة لعرض كلمة مرور Crest هذه.",
            "Changes which Space supplies cookies and passwords": "يغيّر المساحة التي توفر ملفات تعريف الارتباط وكلمات المرور",
            "Checking saved passwords": "جارٍ التحقق من كلمات المرور المحفوظة",
            "Copy Password": "نسخ كلمة المرور",
            "Crest couldn’t authenticate and read that password from this Space.": "تعذّر على Crest المصادقة وقراءة كلمة المرور هذه من هذه المساحة.",
            "Crest couldn’t copy that password.": "تعذّر على Crest نسخ كلمة المرور هذه.",
            "Crest does not save this session or use Crest Passwords. Website data stays in memory only.": "لا يحفظ Crest هذه الجلسة ولا يستخدم كلمات مرور Crest. تبقى بيانات مواقع الويب في الذاكرة فقط.",
            "Crest iCloud sync on": "مزامنة Crest عبر iCloud مفعّلة",
            "Crest password suggestions": "اقتراحات كلمات مرور Crest",
            "Crest Passwords": "كلمات مرور Crest",
            "Crest Passwords remain private to this Space. System Passwords and passkeys are provider-managed and may appear in any Space for the matching site.": "تظل كلمات مرور Crest خاصة بهذه المساحة. تُدار «كلمات السر» ومفاتيح المرور بواسطة موفري النظام وقد تظهر في أي مساحة للموقع المطابق.",
            "Crest Passwords stay in this Space. They never enter another Space’s suggestions or records.": "تبقى كلمات مرور Crest في هذه المساحة. ولا تدخل مطلقًا في اقتراحات أو سجلات مساحة أخرى.",
            "Crest requires Touch ID, Face ID, or the device password before every reveal or copy. A revealed password hides after 30 seconds; a copied password expires after 60 seconds.": "يتطلب Crest استخدام بصمة الإصبع أو بصمة الوجه أو رمز دخول الجهاز قبل كل إظهار أو نسخ. تُخفى كلمة المرور الظاهرة بعد 30 ثانية، وتنتهي صلاحية النسخة بعد 60 ثانية.",
            "Crest shows descriptor metadata only. Password values stay in the active Space’s Data Protection Keychain and never enter session or CloudKit data.": "يعرض Crest بيانات وصفية فقط. تبقى قيم كلمات المرور في سلسلة مفاتيح حماية البيانات للمساحة النشطة ولا تدخل مطلقًا في بيانات الجلسة أو CloudKit.",
            "Delete Password": "حذف كلمة المرور",
            "Delete Password?": "هل تريد حذف كلمة المرور؟",
            "Export Passwords": "تصدير كلمات المرور",
            "Export Passwords as Plaintext?": "هل تريد تصدير كلمات المرور كنص عادي؟",
            "Export Passwords…": "تصدير كلمات المرور…",
            "Extensions Off in Private Browsing": "الإضافات متوقفة في التصفح الخاص",
            "Hide Password": "إخفاء كلمة المرور",
            "Manage Saved Passwords…": "إدارة كلمات المرور المحفوظة…",
            "No Crest passwords are saved for this site in this Space.": "لا توجد كلمات مرور Crest محفوظة لهذا الموقع في هذه المساحة.",
            "No Matching Passwords": "لا توجد كلمات مرور مطابقة",
            "No Saved Passwords": "لا توجد كلمات مرور محفوظة",
            "Offer a copy to Passwords": "عرض نسخة على «كلمات السر»",
            "Offer a copy to Passwords on iPhone and iPad": "عرض نسخة على «كلمات السر» في iPhone وiPad",
            "Only account and site metadata is shown here. Password values stay in the selected Space’s Data Protection Keychain and never enter Crest session or CloudKit records.": "يتم عرض بيانات الحساب والموقع فقط هنا. تبقى قيم كلمات المرور في سلسلة مفاتيح حماية البيانات للمساحة المحددة ولا تدخل مطلقًا في سجلات جلسة Crest أو CloudKit.",
            "Passkeys belong to the system account and may appear in any Space. The page’s cookies and sign-in session remain in the active Space.": "تنتمي مفاتيح المرور إلى حساب النظام وقد تظهر في أي مساحة. وتظل ملفات تعريف الارتباط وجلسة تسجيل الدخول الخاصة بالصفحة في المساحة النشطة.",
            "Password": "كلمة المرور",
            "Password hidden": "كلمة المرور مخفية",
            "Password visible": "كلمة المرور ظاهرة",
            "Passwords": "كلمات المرور",
            "Passwords App": "تطبيق «كلمات السر»",
            "Passwords for": "كلمات المرور لـ",
            "Passwords in": "كلمات المرور في",
            "Passwords in %@": "كلمات المرور في %@",
            "Passwords Off in Private Browsing": "كلمات المرور متوقفة في التصفح الخاص",
            "Reading this Space’s Keychain…": "جارٍ قراءة سلسلة مفاتيح هذه المساحة…",
            "Removing private browser data…": "جارٍ إزالة بيانات التصفح الخاص…",
            "Requesting passkey access": "جارٍ طلب الوصول إلى مفاتيح المرور",
            "Reveal Password": "إظهار كلمة المرور",
            "Saved passwords": "كلمات المرور المحفوظة",
            "Saving password": "جارٍ حفظ كلمة المرور",
            "Search accounts or sites": "البحث في الحسابات أو المواقع",
            "Sync this Space’s Crest passwords with iCloud Keychain": "مزامنة كلمات مرور Crest في هذه المساحة مع سلسلة مفاتيح iCloud",
            "Sync with iCloud Keychain": "المزامنة مع سلسلة مفاتيح iCloud",
            "Synchronized through Crest’s iCloud Keychain item": "تتم المزامنة عبر عنصر سلسلة مفاتيح iCloud الخاص بـ Crest",
            "System Passkeys": "مفاتيح مرور النظام",
            "System passkeys": "مفاتيح مرور النظام",
            "System passkeys: %@": "مفاتيح مرور النظام: %@",
            "The CSV file will contain readable usernames and passwords from only the selected Space. Anyone with the file can read them. Crest will authenticate you before opening the Files picker.": "سيحتوي ملف CSV على أسماء مستخدمين وكلمات مرور مقروءة من المساحة المحددة فقط. يمكن لأي شخص لديه الملف قراءتها. سيقوم Crest بمصادقتك قبل فتح منتقي «الملفات».",
            "The CSV file will contain readable usernames and passwords from only the selected Space. Anyone with the file can read them. Crest will authenticate you before opening the save panel.": "سيحتوي ملف CSV على أسماء مستخدمين وكلمات مرور مقروءة من المساحة المحددة فقط. يمكن لأي شخص لديه الملف قراءتها. سيقوم Crest بمصادقتك قبل فتح لوحة الحفظ.",
            "The local encrypted-record projection is active. Production CloudKit transport remains unavailable until the iCloud container and entitlements are activated in the developer portal.": "إسقاط السجلات المشفرة المحلي نشط. يظل نقل CloudKit الإنتاجي غير متاح حتى يتم تفعيل حاوية iCloud والاستحقاقات في بوابة المطور.",
            "This credential belongs to the embedded %@ frame, not %@.": "تنتمي بيانات الاعتماد هذه إلى إطار %1$@ المضمّن، وليس إلى %2$@.",
            "Updating existing credentials…": "جارٍ تحديث بيانات الاعتماد الموجودة…",
            "Updating existing Keychain items…": "جارٍ تحديث عناصر سلسلة المفاتيح الموجودة…",
            "Updating this Space’s saved passwords…": "جارٍ تحديث كلمات المرور المحفوظة في هذه المساحة…",
            "Username": "اسم المستخدم",
            "View Password": "عرض كلمة المرور",
            "WebKit presents the person’s enabled Passwords providers for AutoFill. An explicit user-approved copy from Crest is not enabled in this build. It is not a system extension and will never require reduced security.": "يعرض WebKit موفري «كلمات السر» الذين فعّلهم المستخدم للتعبئة التلقائية. لا تتوفر في هذا الإصدار نسخة صريحة يوافق المستخدم على نقلها من Crest. وهذه ليست إضافة نظام ولن تتطلب مطلقًا تقليل مستوى الأمان.",
        ]

        for (key, expectedValue) in expectedArabic {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], key)
            let localizations = try XCTUnwrap(
                entry["localizations"] as? [String: Any],
                key
            )
            let arabic = try XCTUnwrap(localizations["ar"] as? [String: Any], key)
            let stringUnit = try XCTUnwrap(arabic["stringUnit"] as? [String: Any], key)
            XCTAssertEqual(stringUnit["value"] as? String, expectedValue, key)
        }
    }

    func testTabsFoldersQuickWindowAndPeekSurfaceResolvesInArabic() throws {
        let catalog = try sourceCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let expectedArabic = [
            "Also available by swiping inward from the leading edge": "متاح أيضًا بالسحب إلى الداخل من الحافة الأمامية",
            "Balanced uses a native WebKit rule list to stop known third-party advertising and tracking requests. It never blocks the top-level page, and this choice affects only the selected Space.": "يستخدم الوضع المتوازن قائمة قواعد أصلية من WebKit لإيقاف طلبات الإعلانات والتتبع المعروفة التابعة لجهات خارجية. وهو لا يحظر الصفحة الرئيسية أبدًا، ويؤثر هذا الخيار في المساحة المحددة فقط.",
            "Choose Destination Space": "اختيار مساحة الوجهة",
            "Clean Up Current Tabs": "تنظيف علامات التبويب الحالية",
            "Clean Up Eligible Tabs Now": "تنظيف علامات التبويب المؤهلة الآن",
            "Close": "إغلاق",
            "Close %@": "إغلاق %@",
            "Close Find": "إغلاق البحث",
            "Close Peek": "إغلاق Peek",
            "Close Peek (⌘W)": "إغلاق Peek (⌘W)",
            "Close Quick Window": "إغلاق النافذة السريعة",
            "Closed and automatically cleaned tabs from this Space appear here.": "تظهر هنا علامات التبويب المغلقة والمنظفة تلقائيًا من هذه المساحة.",
            "Collapses this folder": "يطوي هذا المجلد",
            "Create a saved-tabs folder in %@.": "إنشاء مجلد لعلامات التبويب المحفوظة في %@.",
            "Create a tab or choose one from the sidebar.": "أنشئ علامة تبويب أو اختر واحدة من الشريط الجانبي.",
            "Crest released this temporary page to reduce memory use.": "حرر Crest هذه الصفحة المؤقتة لتقليل استخدام الذاكرة.",
            "Current": "الحالية",
            "Current tabs": "علامات التبويب الحالية",
            "Delete Folder": "حذف المجلد",
            "Destination": "الوجهة",
            "Drop a tab here to make it a current tab": "أفلت علامة تبويب هنا لجعلها علامة تبويب حالية",
            "Drop a tab here to pin it": "أفلت علامة تبويب هنا لتثبيتها",
            "Drop a tab here to save it": "أفلت علامة تبويب هنا لحفظها",
            "Eligible tabs remain recoverable from Archive.": "تبقى علامات التبويب المؤهلة قابلة للاسترداد من الأرشيف.",
            "Expands this folder": "يوسّع هذا المجلد",
            "Folder Name": "اسم المجلد",
            "iPad keeps the sidebar, address field, and page frame visible.": "يحافظ iPad على ظهور الشريط الجانبي وحقل العنوان وإطار الصفحة.",
            "iPhone uses a full-screen tab viewer and bottom page address bar.": "يستخدم iPhone عارض علامات تبويب بملء الشاشة وشريط عنوان أسفل الصفحة.",
            "Its tabs stay saved, and any nested folders move up one level.": "تبقى علامات التبويب الخاصة به محفوظة، وتنتقل أي مجلدات متداخلة إلى مستوى أعلى.",
            "Match": "مطابقة",
            "Match found": "تم العثور على مطابقة",
            "Most Recent Tab": "أحدث علامة تبويب",
            "Move Down": "تحريك لأسفل",
            "Move the pointer to the leading edge to show the sidebar": "حرّك المؤشر إلى الحافة الأمامية لإظهار الشريط الجانبي",
            "Move to Current Tabs": "نقل إلى علامات التبويب الحالية",
            "Move to Folder": "نقل إلى مجلد",
            "Move to Space": "نقل إلى مساحة",
            "Move Up": "تحريك لأعلى",
            "New Nested Folder": "مجلد متداخل جديد",
            "New tab": "علامة تبويب جديدة",
            "New Tab (⌘T)": "علامة تبويب جديدة (⌘T)",
            "Next Match": "المطابقة التالية",
            "Next Tab (Bracket)": "علامة التبويب التالية (القوس)",
            "No match": "لا توجد مطابقة",
            "No Tab Selected": "لم يتم تحديد علامة تبويب",
            "Open cross-site links from pinned and saved tabs in Peek": "فتح الروابط بين المواقع من علامات التبويب المثبتة والمحفوظة في Peek",
            "Open in": "فتح في",
            "Open in %@": "فتح في %@",
            "Open in another Space": "فتح في مساحة أخرى",
            "Open Tab": "فتح علامة التبويب",
            "Opening in another Space reloads the page inside that Space’s independent website-data store.": "يؤدي الفتح في مساحة أخرى إلى إعادة تحميل الصفحة داخل مخزن بيانات مواقع الويب المستقل لتلك المساحة.",
            "Opening Peek…": "جارٍ فتح Peek…",
            "Opening Quick Window…": "جارٍ فتح النافذة السريعة…",
            "Opens a new Start Page. Swipe down to return to the selected tab.": "يفتح صفحة بداية جديدة. اسحب لأسفل للعودة إلى علامة التبويب المحددة.",
            "Option-click opens any web link in Peek. Dismiss with Escape, ⌘W, the close button, or the outside area; ⌘O expands it into a current tab.": "يؤدي النقر مع الضغط على Option إلى فتح أي رابط ويب في Peek. يمكنك الإغلاق باستخدام Escape أو ⌘W أو زر الإغلاق أو المنطقة الخارجية؛ ويؤدي ⌘O إلى توسيعه إلى علامة تبويب حالية.",
            "Page": "الصفحة",
            "Page Stopped": "توقفت الصفحة",
            "Page Zoom": "تكبير الصفحة",
            "Peek": "Peek",
            "Peek Released": "تم تحرير Peek",
            "Pin or Unpin Tab": "تثبيت علامة التبويب أو إلغاء تثبيتها",
            "Pin Tab": "تثبيت علامة التبويب",
            "Pinned": "مثبتة",
            "Pinned tabs": "علامات التبويب المثبتة",
            "Pinned, saved, folder, and current tabs support live reordering.": "تدعم علامات التبويب المثبتة والمحفوظة والمجلدات وعلامات التبويب الحالية إعادة الترتيب المباشر.",
            "Previous Match": "المطابقة السابقة",
            "Previous Tab (Bracket)": "علامة التبويب السابقة (القوس)",
            "Quick destinations": "الوجهات السريعة",
            "Quick Window": "النافذة السريعة",
            "Quick Window address": "عنوان النافذة السريعة",
            "Quick Window Released": "تم تحرير النافذة السريعة",
            "Quick Window Space": "مساحة النافذة السريعة",
            "Reload Page": "إعادة تحميل الصفحة",
            "Reload Peek": "إعادة تحميل Peek",
            "Rename Folder": "إعادة تسمية المجلد",
            "Rename Tab": "إعادة تسمية علامة التبويب",
            "Rename Tab…": "إعادة تسمية علامة التبويب…",
            "Save in Folder": "حفظ في مجلد",
            "Saved": "محفوظة",
            "Saved and current tabs": "علامات التبويب المحفوظة والحالية",
            "Saved decisions": "القرارات المحفوظة",
            "Saved tabs": "علامات التبويب المحفوظة",
            "Saved Tabs": "علامات التبويب المحفوظة",
            "Search and cleanup are owned by each Space. Cleanup moves inactive current tabs to Archive and never removes the selected tab.": "ينتمي البحث والتنظيف إلى كل مساحة. ينقل التنظيف علامات التبويب الحالية غير النشطة إلى الأرشيف ولا يزيل علامة التبويب المحددة مطلقًا.",
            "Search and cleanup stay independent in every Space. Cleanup archives inactive current tabs and preserves the selected tab.": "يظل البحث والتنظيف مستقلين في كل مساحة. يؤرشف التنظيف علامات التبويب الحالية غير النشطة ويحافظ على علامة التبويب المحددة.",
            "Start Page search": "بحث صفحة البداية",
            "Tab Name": "اسم علامة التبويب",
            "Tab Unloaded": "تم إلغاء تحميل علامة التبويب",
            "Tabs reorder live across pinned, saved, folder, and current sections.": "يُعاد ترتيب علامات التبويب مباشرةً بين الأقسام المثبتة والمحفوظة والمجلدات والحالية.",
            "The new folder will appear inside %@.": "سيظهر المجلد الجديد داخل %@.",
            "The page sits inside a Space-colored window frame.": "تقع الصفحة داخل إطار نافذة بلون المساحة.",
            "The web content process stopped repeatedly. Your tab and last address are still available.": "توقفت عملية محتوى الويب بشكل متكرر. لا تزال علامة التبويب وآخر عنوان متاحين.",
            "This tab is still pinned or saved, but its web page is not using memory.": "لا تزال علامة التبويب هذه مثبتة أو محفوظة، لكن صفحة الويب الخاصة بها لا تستخدم الذاكرة.",
            "Unload Tab": "إلغاء تحميل علامة التبويب",
        ]

        for (key, expectedValue) in expectedArabic {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], key)
            let localizations = try XCTUnwrap(
                entry["localizations"] as? [String: Any],
                key
            )
            let arabic = try XCTUnwrap(localizations["ar"] as? [String: Any], key)
            let stringUnit = try XCTUnwrap(arabic["stringUnit"] as? [String: Any], key)
            XCTAssertEqual(stringUnit["value"] as? String, expectedValue, key)
        }
    }

    func testEveryHousePaletteNameIsTranslatedForArabic() throws {
        // The swatch label goes through the catalog by name, so a palette that is
        // missing an entry would silently ship its English design-token name.
        let arabic = try localizedStrings(in: .main, localization: "ar")
        let expected = [
            "Winter": "الشتاء",
            "Lion": "الأسد",
            "Storm": "العاصفة",
            "Dragon": "التنين",
            "Meadow": "المرج",
            "Iron": "الحديد",
            "River": "النهر",
            "Sun": "الشمس",
            "Vigil": "اليقظة"
        ]

        for palette in BrowserSpaceHousePalette.allCases {
            XCTAssertEqual(arabic[palette.name], expected[palette.name], palette.name)
        }
        XCTAssertEqual(
            Set(BrowserSpaceHousePalette.allCases.map(\.name)),
            Set(expected.keys)
        )
    }

    func testMacApplicationBundlesTheArabicCoreBrowserCatalog() throws {
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

    private func localized(
        _ source: LocalizedStringResource,
        locale: Locale
    ) -> String {
        var resource = source
        resource.locale = locale
        return String(localized: resource)
    }

    private func hasCompleteTranslation(_ node: [String: Any]) -> Bool {
        if let stringUnit = node["stringUnit"] as? [String: Any] {
            return stringUnit["state"] as? String == "translated"
                && !(stringUnit["value"] as? String ?? "").isEmpty
        }

        guard let variations = node["variations"] as? [String: Any] else {
            return false
        }
        let children = translatedVariationChildren(in: variations)
        return !children.isEmpty && children.allSatisfy(hasCompleteTranslation)
    }

    private func translatedVariationChildren(
        in node: [String: Any]
    ) -> [[String: Any]] {
        node.values.flatMap { value -> [[String: Any]] in
            guard let child = value as? [String: Any] else { return [] }
            if child["stringUnit"] != nil {
                return [child]
            }
            return translatedVariationChildren(in: child)
        }
    }
}
