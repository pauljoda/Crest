import SwiftUI

/// Everything the sidebar's address field is told, and the answers that follow
/// from it.
///
/// `hasActiveSite` is the one thing the field cannot work out for itself. The
/// controls a live site contributes — a certificate button in the leading slot,
/// a site-settings button in the trailing one — belong to the shell that owns
/// pages, so the field is told only *that* they exist and decides when the slots
/// are theirs.
@MainActor
struct BrowserSidebarAddressFieldConfiguration {
    let text: Binding<String>
    let isEditing: Binding<Bool>
    var focusRequest = 0
    let isSecure: Bool
    let progress: Double
    let isLoading: Bool
    /// Whether the selected tab is actually holding a page right now. A tab
    /// that has an address but no page behind it keeps the placeholder glyph
    /// away, so a restored-but-unloaded tab does not read as a live site.
    var hasResidentPage = true
    /// Whether a live site is offering the field its own controls.
    var hasActiveSite = false
    let capabilities: BrowserInteractionCapabilities
    /// What tapping the resting address means. Absent where the field simply
    /// begins editing in place; present where the shell grows it into the
    /// command palette instead.
    let activate: (() -> Void)?
    let submit: () -> Void
    let morphNamespace: Namespace.ID
    let morphID: String
    var addressAccessibilityLabel: LocalizedStringKey = "Address and search"
    var addressAccessibilityIdentifier = "address-field"
    var addressDisplayAccessibilityIdentifier = "address-display"
    var prompt: LocalizedStringKey = "Search or enter website"

    var metrics: BrowserSidebarAddressFieldMetrics {
        BrowserSidebarInteractionPolicy.addressFieldMetrics(capabilities)
    }

    /// Whether the live site's own control takes the leading slot.
    var showsLeadingAccessory: Bool {
        BrowserAddressSecurityControlPolicy.isVisible(
            isAddressEditing: isEditing.wrappedValue,
            hasActiveSite: hasActiveSite
        )
    }

    /// Whether the lock-or-search glyph stands in the leading slot instead.
    var showsPlaceholderGlyph: Bool {
        BrowserAddressLeadingControlPolicy.showsPlaceholderGlyph(
            isAddressEditing: isEditing.wrappedValue,
            hasActiveSite: hasActiveSite,
            hasAddress: !text.wrappedValue.isEmpty,
            hasResidentPage: hasResidentPage
        )
    }

    /// Whether the live site's settings control takes the trailing slot.
    var showsTrailingAccessory: Bool {
        BrowserSiteControlPresentationPolicy.isVisible(
            isAddressEditing: isEditing.wrappedValue,
            hasActiveSite: hasActiveSite
        )
    }

    /// The clear control appears while there is an edit in progress and
    /// something to undo, on every shell.
    var showsClearControl: Bool {
        isEditing.wrappedValue && !text.wrappedValue.isEmpty
    }
}
