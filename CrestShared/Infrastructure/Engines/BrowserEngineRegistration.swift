import Foundation

/// The adapter descriptors each composition can select. `current` comes from
/// the composition (`BrowserEngineRegistration+Composition.swift` for WebKit,
/// the Chromium framework's own extension otherwise).
enum BrowserEngineRegistration {

    // MARK: - Variables

    #if os(macOS)
        private static let webKitImplementation = BrowserEngineImplementation.webKitMacOS
    #else
        private static let webKitImplementation = BrowserEngineImplementation.webKitIOS
    #endif

    static let webKit = BrowserAdapterRegistration(
        implementation: webKitImplementation,
        scope: "Native \(webKitImplementation.platformName.lowercased()) page and profile ports",
        supported: [
            .pages, .navigation, .find, .zoom, .interactionState, .pageResidency,
            .popups, .workspaceProfiles, .workspaceTransfer, .profileDeletion,
            .contentBlocking, .downloads, .permissions, .reader, .translation,
            .selectionTranslation, .localFiles,
        ] + desktopWebKit,
        unavailable: [.extensions],
        limitations: [
            "A staged Peek navigation replays only a GET link's URL and referrer; WebKit has no public way to carry the initiating frame's origin, user activation or sandbox into another page."
        ] + desktopWebKitLimitations,
        archiveFormat: .webKit,
        evidence: "Existing native WebKit services and retained page, popup, profile and navigation contracts")

    static let chromium = BrowserAdapterRegistration(
        implementation: .chromiumMacOS,
        scope: "Native macOS Chromium host with Crest page and profile ports",
        supported: [
            .pages, .navigation, .find, .zoom, .interactionState, .pageResidency,
            .workspaceProfiles, .workspaceTransfer, .profileDeletion,
            .beforeUnload, .downloads, .permissions, .viewportCapture, .inspector, .internalPages,
            .fullPageCapture, .pdf, .webArchive, .print, .localFiles,
            .extensions, .selectionTranslation, .popups, .featureFlags,
        ],
        unavailable: [.reader, .translation, .contentBlocking],
        limitations: [
            "Find does not honour a non-wrapping search: the host command takes no wrap argument and the engine always wraps.",
            "Extensions cover actions, installation, side panels and per-Space permissions; full API parity and Apple password-helper pairing remain incomplete.",
            "Translation is limited to the selection service; whole-page translation is unavailable.",
            "Site permission decisions reach the engine as content settings for the page's current site; the host has no command to stop live camera, microphone or location use directly, so revocation relies on the engine ending it when the setting blocks.",
            "Web notifications are delivered through the engine's own notification path; Crest's system delivery, activation of the source tab and withdrawal of delivered notifications after revocation need a host notification hook.",
        ],
        archiveFormat: .mhtml,
        evidence: "Native host page, lifecycle, download, permission and compositor ports; isolated app validation")

    private static var desktopWebKit: [BrowserEngineCapability] {
        #if os(macOS)
            [.viewportCapture, .fullPageCapture, .pdf, .webArchive, .print, .inspector, .featureFlags, .beforeUnload]
        #else
            []
        #endif
    }

    private static var desktopWebKitLimitations: [String] {
        #if os(macOS)
            [
                "Before-unload uses WebKit's desktop close and prompt SPI; a WebKit without it closes pages without asking."
            ]
        #else
            []
        #endif
    }
}
