import Foundation

/// A forwarder kept only for call sites other batches own (CrestMobile and the
/// sidebar, chrome and Spaces features). Delete it once they read
/// `branding.foregroundTone` directly.
enum BrowserSpaceForegroundPolicy {
    static func tone(for branding: SpaceBranding) -> BrowserSpaceForegroundTone {
        branding.foregroundTone
    }
}
