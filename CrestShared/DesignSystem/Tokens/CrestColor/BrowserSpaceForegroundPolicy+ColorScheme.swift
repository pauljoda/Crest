import SwiftUI

/// Forwarders kept only for call sites other batches own. Delete them once
/// those call sites read `branding.foregroundTone.colorScheme` and
/// `color.foregroundTone.colorScheme` directly.
extension BrowserSpaceForegroundPolicy {
    static func colorScheme(for branding: SpaceBranding) -> ColorScheme {
        branding.foregroundTone.colorScheme
    }

    static func colorScheme(over color: BrandColor) -> ColorScheme {
        color.foregroundTone.colorScheme
    }
}
