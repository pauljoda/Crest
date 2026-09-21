import Foundation

/// The versioned descriptor shared by native page ports and message adapters.
/// A declaration describes this adapter's integration, not every feature of its engine.
struct BrowserAdapterRegistration: Encodable, Sendable {
    struct Capability: Encodable, Sendable {
        let status: String
        let contractVersion = 1
        let scope: String
        let limitations: [String]
        let evidence: String
    }
    let adapterId: String
    let role: String
    let implementationId: String
    let implementationVersion = "1"
    let protocolVersion = 1
    let capabilities: [String: Capability]

    init(id: String, role: String, implementation: String, scope: String,
         supported: [String], unverified: [String] = [], unavailable: [String] = [],
         limitations: [String] = [], evidence: String) {
        adapterId = id; self.role = role; implementationId = implementation
        var values: [String: Capability] = [:]
        for (status, names) in [("supported", supported), ("unverified", unverified), ("unavailable", unavailable)] {
            for name in names {
                precondition(values[name] == nil, "Duplicate adapter capability: \(name)")
                values[name] = Capability(status: status, scope: scope, limitations: limitations, evidence: evidence)
            }
        }
        capabilities = values
    }
    func supports(_ name: String) -> Bool {
        capabilities[name]?.status == "supported" && capabilities[name]?.contractVersion == 1
    }
    func encoded() throws -> Data { try JSONEncoder().encode(self) }
}

enum BrowserEngineRegistration {
    #if os(macOS)
    static let platform = "macos"
    #else
    static let platform = "ios"
    #endif

    /// Selected by the process composition, never by synced Space records.
    static var current: BrowserAdapterRegistration {
        #if CREST_CHROMIUM_HOST
        chromium
        #else
        webKit
        #endif
    }

    static let webKit = BrowserAdapterRegistration(
        id: "engine", role: "engine", implementation: "crest.webkit.\(platform)",
        scope: "Native \(platform) page and profile ports",
        supported: ["pages", "navigation", "find", "zoom", "interaction-state", "page-residency",
                    "popups", "workspace-profiles", "workspace-transfer", "profile-deletion",
                    "content-blocking", "downloads", "permissions", "reader", "translation"] + desktopWebKit,
        unavailable: ["extensions"],
        evidence: "Existing native WebKit services and retained page, popup, profile and navigation contracts")

    private static var desktopWebKit: [String] {
        #if os(macOS)
        ["viewport-capture", "full-page-capture", "pdf", "web-archive", "print", "inspector"]
        #else
        []
        #endif
    }

    static let chromium = BrowserAdapterRegistration(
        id: "engine", role: "engine", implementation: "crest.chromium.macos",
        scope: "Native macOS Chromium host with Crest page and profile ports",
        supported: ["pages", "navigation", "find", "zoom", "interaction-state", "page-residency",
                    "popups", "workspace-profiles", "workspace-transfer", "profile-deletion",
                    "before-unload", "downloads", "permissions", "viewport-capture", "inspector", "internal-pages",
                    "full-page-capture", "pdf", "web-archive", "print"],
        unverified: ["extensions"],
        unavailable: ["reader", "translation", "content-blocking"],
        limitations: ["Extension actions and installation are wired; full API parity and Apple password-helper pairing remain incomplete."],
        evidence: "Native host page, lifecycle, download, permission and compositor ports; isolated app validation")
}
