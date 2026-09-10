import Foundation
import WebKit

@MainActor
enum BrowserTranslationDocument {
    struct Sample: Sendable {
        let text: String
        let declaredLanguage: String
    }

    struct Capture {
        let texts: [String]
        let isLimited: Bool
    }

    struct Update: Sendable {
        let index: Int
        let text: String
    }

    static let world = WKContentWorld.world(name: "Crest.PageTranslation")

    static func sample(in webView: WKWebView) async throws -> Sample {
        let value = try await perform("sample", in: webView) as? [String: Any]
        return Sample(text: value?["text"] as? String ?? "", declaredLanguage: value?["language"] as? String ?? "")
    }

    static func capture(in webView: WKWebView, token: String) async throws -> Capture {
        let value = try await perform("capture", token: token, in: webView) as? [String: Any]
        return Capture(texts: value?["texts"] as? [String] ?? [], isLimited: value?["limited"] as? Bool ?? false)
    }

    static func apply(_ texts: [String], offset: Int, token: String, in webView: WKWebView) async throws -> Int {
        try await perform("apply", token: token, texts: texts, offset: offset, in: webView) as? Int ?? 0
    }

    static func restore(token: String, in webView: WKWebView) async throws {
        _ = try await perform("restore", token: token, in: webView)
    }

    static func apply(_ updates: [Update], token: String, in webView: WKWebView) async throws -> Int {
        try await perform(
            "apply", token: token, texts: updates.map(\.text), indices: updates.map(\.index), in: webView
        ) as? Int ?? 0
    }

    private static func perform(
        _ action: String, token: String = "", texts: [String] = [], offset: Int = 0,
        indices: [Int] = [], in webView: WKWebView
    ) async throws -> Any? {
        try await webView.callAsyncJavaScript(
            BrowserTranslationJavaScript.source,
            arguments: ["action": action, "token": token, "texts": texts, "offset": offset, "indices": indices],
            in: nil, contentWorld: world
        )
    }
}
