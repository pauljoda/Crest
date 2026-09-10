import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserPageTranslationTests: XCTestCase {
    func testPreferredTargetSurvivesAMissingCatalogAndPreservesThePreferredScript() {
        let english = Locale.Language(identifier: "en-US")
        XCTAssertEqual(BrowserTranslationPreference.preferredTarget(in: [], preferred: english), english)
        let traditional = Locale.Language(identifier: "zh-Hant")
        let available = [Locale.Language(identifier: "zh-Hans"), traditional, english]
        XCTAssertEqual(
            BrowserTranslationPreference.preferredTarget(in: available, preferred: traditional), traditional)
    }

    func testOffersDoNotTranslateUntilRequestedAndShowingOriginalSuppressesAutomaticRetry() async throws {
        let web = try await fixture()
        let translation = BrowserPageTranslation()
        translation.setActive(true, in: web)
        await translation.detect(in: web)
        await translation.automaticallyTranslateIfAvailable(enabled: false)
        XCTAssertNil(translation.configuration, "Detection must never request translation or a model download.")
        XCTAssertFalse(translation.isWorking)
        translation.dismiss()
        translation.targetID = "en"
        translation.start()
        XCTAssertTrue(translation.showsToolbar, "Starting from Page Actions must reveal translation controls.")
        XCTAssertNotNil(translation.configuration)
        translation.showOriginal()
        await translation.automaticallyTranslateIfAvailable(enabled: true)
        XCTAssertFalse(translation.isWorking, "Show Original must suppress automatic translation for this document.")
        XCTAssertNil(translation.configuration)
        translation.reset()
        XCTAssertFalse(translation.isOffered)
        XCTAssertNil(translation.configuration)
    }

    func testToolbarVisibilityPreservesThePendingTranslationAndResetsWithItsDocument() async throws {
        let web = try await fixture()
        let translation = BrowserPageTranslation()
        translation.setActive(true, in: web)
        translation.sourceID = "es"
        translation.targetID = "en"
        translation.start()
        let configuration = try XCTUnwrap(translation.configuration)
        XCTAssertTrue(translation.isWorking)
        translation.setToolbarVisible(false)
        XCTAssertFalse(translation.showsToolbar)
        XCTAssertTrue(translation.isWorking)
        XCTAssertEqual(translation.configuration, configuration)
        translation.toggleToolbarVisibility()
        XCTAssertTrue(translation.showsToolbar)
        XCTAssertEqual(translation.configuration, configuration)
        translation.reset()
        XCTAssertFalse(translation.showsToolbar)
        XCTAssertFalse(translation.isWorking)
        XCTAssertNil(translation.configuration)
    }

    func testTranslationPreservesEditableContentAndWebsiteChangesOnRestore() async throws {
        let web = try await fixture()
        let capture = try await BrowserTranslationDocument.capture(in: web, token: "first")
        XCTAssertTrue(capture.texts.contains("Hola mundo"))
        XCTAssertTrue(capture.texts.contains("Enviar"))
        XCTAssertFalse(capture.texts.contains("secret"))
        XCTAssertFalse(capture.texts.contains("no traducir"))
        let translated = capture.texts.enumerated().reversed().map {
            BrowserTranslationDocument.Update(index: $0.offset, text: "Translated " + $0.element)
        }
        _ = try await BrowserTranslationDocument.apply(translated, token: "first", in: web)
        let heading = try await web.evaluateJavaScript("document.querySelector('h1').textContent") as? String
        XCTAssertEqual(heading, "Translated Hola mundo", "Streamed responses can arrive out of document order.")
        _ = try await web.evaluateJavaScript(
            "document.querySelector('input').value='edited'; document.querySelector('#live').firstChild.data='Site update';"
        )
        try await BrowserTranslationDocument.restore(token: "first", in: web)
        let values =
            try await web.evaluateJavaScript(
                "[document.querySelector('h1').textContent,document.querySelector('input').value,document.querySelector('#live').textContent,document.querySelector('a').getAttribute('href')]"
            ) as? [String]
        XCTAssertEqual(values, ["Hola mundo", "edited", "Site update", "#next"])
    }

    func testRetiredOperationCannotApplyOrRestoreOverANewerTranslation() async throws {
        let web = try await fixture()
        let first = try await BrowserTranslationDocument.capture(in: web, token: "first")
        let second = try await BrowserTranslationDocument.capture(in: web, token: "second")
        let stale = try await BrowserTranslationDocument.apply(
            first.texts.map { _ in "Stale" }, offset: 0, token: "first", in: web)
        XCTAssertEqual(stale, 0)
        _ = try await BrowserTranslationDocument.apply(
            second.texts.map { _ in "Current" }, offset: 0, token: "second", in: web)
        try await BrowserTranslationDocument.restore(token: "first", in: web)
        let heading = try await web.evaluateJavaScript("document.querySelector('h1').textContent") as? String
        XCTAssertEqual(heading, "Current")
        try await BrowserTranslationDocument.restore(token: "second", in: web)
    }

    func testPageHideRestoresTextBeforeTheDocumentCanBeCached() async throws {
        let web = try await fixture()
        let capture = try await BrowserTranslationDocument.capture(in: web, token: "cached")
        _ = try await BrowserTranslationDocument.apply(
            capture.texts.map { _ in "Translated" }, offset: 0, token: "cached", in: web)
        _ = try await web.evaluateJavaScript(
            "window.dispatchEvent(new PageTransitionEvent('pagehide', {persisted:true}))")
        let heading = try await web.evaluateJavaScript("document.querySelector('h1').textContent") as? String
        XCTAssertEqual(heading, "Hola mundo")
        let late = try await BrowserTranslationDocument.apply(capture.texts, offset: 0, token: "cached", in: web)
        XCTAssertEqual(late, 0)
    }

    func testNewDocumentRejectsOldResultsEvenAtTheSameURL() async throws {
        let web = try await fixture()
        let capture = try await BrowserTranslationDocument.capture(in: web, token: "old")
        web.loadHTMLString("<h1>New document</h1>", baseURL: URL(string: "https://translation.crest.test"))
        try await waitForLoad(web)
        let applied = try await BrowserTranslationDocument.apply(capture.texts, offset: 0, token: "old", in: web)
        XCTAssertEqual(applied, 0)
    }

    func testRouteChangeRejectsLateResultsButAnchorNavigationKeepsTranslation() async throws {
        let web = try await fixture()
        let capture = try await BrowserTranslationDocument.capture(in: web, token: "route")
        _ = try await web.evaluateJavaScript("history.pushState({}, '', '#next')")
        let applied = try await BrowserTranslationDocument.apply(
            capture.texts.map { _ in "Translated" }, offset: 0, token: "route", in: web)
        XCTAssertEqual(applied, capture.texts.count)
        try await BrowserTranslationDocument.restore(token: "route", in: web)
        _ = try await BrowserTranslationDocument.capture(in: web, token: "route-two")
        _ = try await web.evaluateJavaScript("history.pushState({}, '', '/new-route')")
        let stale = try await BrowserTranslationDocument.apply(
            capture.texts.map { _ in "Stale" }, offset: 0, token: "route-two", in: web)
        XCTAssertEqual(stale, 0)
    }

    func testDetectionSamplesBoundedTextWithoutChangingTheDocument() async throws {
        let web = try await fixture()
        _ = try await web.evaluateJavaScript("document.querySelector('h1').textContent = 'hola '.repeat(1500)")
        let sample = try await BrowserTranslationDocument.sample(in: web)
        XCTAssertLessThanOrEqual(sample.text.count, 3000)
        XCTAssertFalse(sample.text.contains("secret"))
        let heading = try await web.evaluateJavaScript("document.querySelector('h1').textContent.length") as? Int
        XCTAssertEqual(heading, 7500)
        let capture = try await BrowserTranslationDocument.capture(in: web, token: "large")
        XCTAssertTrue(capture.isLimited)
    }

    func testSparseJapanesePageUsesDeclaredLanguageAndEmptyPagesDoNotOfferTranslation() async throws {
        let sample = BrowserTranslationDocument.Sample(text: "Google ログイン すべて 画像 動画 ニュース", declaredLanguage: "ja")
        XCTAssertEqual(BrowserPageTranslation.detectedLanguage(in: sample), "ja")
        XCTAssertNil(BrowserPageTranslation.detectedLanguage(in: .init(text: "", declaredLanguage: "ja")))
        XCTAssertEqual(
            BrowserPageTranslation.detectedLanguage(in: .init(text: "日本語のページを表示しています。", declaredLanguage: "ja")), "ja")
    }

    private func fixture() async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        web.loadHTMLString(
            """
            <html lang="es"><body><h1>Hola mundo</h1><p id="live">Noticias nuevas</p>
            <a href="#next">Continuar</a><label>Nombre<input value="secret"></label>
            <textarea>secret</textarea><div contenteditable>secret</div><button>Enviar</button>
            <p translate="no">no traducir</p><p hidden>secret</p><script>const secret = 'secret';</script>
            </body></html>
            """, baseURL: URL(string: "https://translation.crest.test"))
        try await waitForLoad(web)
        return web
    }

    private func waitForLoad(_ web: WKWebView) async throws {
        for _ in 0..<100 {
            if !web.isLoading, (try? await web.evaluateJavaScript("document.readyState")) as? String == "complete" {
                return
            }
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTFail("Translation fixture did not load")
    }
}
