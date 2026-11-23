import SwiftUI

// MARK: - Types

struct BrowserEngineBenefit {
    let title: LocalizedStringResource
    let symbol: String
}

/// Describes a selectable engine with its own artwork and capabilities.
struct BrowserEngineOption: Identifiable {
    // MARK: - Static Variables

    static let all: [BrowserEngineOption] = [
        BrowserEngineOption(
            engine: .chromium, logo: "EngineChromium",
            summary: "Chromium without Google’s data collection. Smooth browsing and extensions.",
            benefits: [
                BrowserEngineBenefit(title: "Smooth webpage performance", symbol: "speedometer"),
                BrowserEngineBenefit(title: "Chrome Web Store extensions", symbol: "puzzlepiece.extension"),
                BrowserEngineBenefit(title: "Protected video, with WebKit fallback", symbol: "play.rectangle"),
            ]),
        BrowserEngineOption(
            engine: .webKit, logo: "EngineWebKit",
            summary: "Apple’s native web engine, with system integration and protected media playback.",
            benefits: [
                BrowserEngineBenefit(title: "Native macOS handling", symbol: "macwindow"),
                BrowserEngineBenefit(title: "FairPlay protected video", symbol: "play.rectangle"),
                BrowserEngineBenefit(title: "Reader Mode", symbol: "doc.text"),
            ]),
    ]

    // MARK: - Variables

    let engine: EngineKind
    let logo: String
    let summary: LocalizedStringResource
    let benefits: [BrowserEngineBenefit]
    var id: EngineKind { engine }

    // MARK: - Actions - Lookup

    /// The name of `engine`'s logo in the app's assets, or nil for an engine
    /// this list does not show.
    static func logo(of engine: EngineKind) -> String? {
        all.first { $0.engine == engine }?.logo
    }
}
