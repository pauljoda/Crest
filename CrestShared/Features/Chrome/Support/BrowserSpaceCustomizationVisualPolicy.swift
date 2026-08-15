import CoreGraphics

enum BrowserSpaceCustomizationVisualPolicy {
    static let usesCompactSpacePicker = true
    static let usesNestedSpaceSidebar = false
    static let showsPersistentBrandingPreview = true
    static let separatesAppearanceFromDetails = true
    static let progressivelyDisclosesFineTuning = true
    static let usesAdaptiveToolbar = true
    static let stacksPreviewBeforeClipping = true
    static let integratesPageIdentityIntoToolbar = true
    static let describesPreviewAsSimplified = true
    static let mobileUsesSharedSidebarPreview = true
    static let mobilePlacesPreviewBeforeControls = true
    static let toolbarShowsExplanatorySubtitle = false
    static let previewMinimumWidth: CGFloat = 240
    static let previewIdealWidth: CGFloat = 260
    static let previewMaximumWidth: CGFloat = 320
    static let editorMinimumWidth: CGFloat = 360
    static let wideEditorMinimumWidth: CGFloat =
        previewIdealWidth
        + editorMinimumWidth
        + 1
    static let sectionPickerWidth: CGFloat = 280
    static let compactSpacePickerWidth: CGFloat = 150
    static let compactSectionPickerWidth: CGFloat = 220
    static let wideIdentityWidth: CGFloat = 120
}
