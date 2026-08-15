import Foundation

enum BrowserQuickWindowChromePolicy {
    static let rendersHistoryControls = false
    static let animatesWindowContent = false
    static let showsSourceSpaceBeforeAddress = true
    static let integratesChromeWithTitlebar = true
    static let sourceSpaceIsInformational = true
    static let destinationHasSpaceSelector = true
    static let usesDedicatedAddressSurface = false
    static let showsSingleMenuIndicator = true
    static let addsCustomToolbarBackingMaterials = false
    static let usesNativeSplitDestinationControl = true
    static let hidesSystemSharedBackgrounds = true
    static let usesSingleToolbarRow = true
    static let usesNativeToolbarPlacements = false
    static let usesRootInlineTitlebarRow = true
    static let embedsSourceSpaceInAddressField = true
    static let reusesMainAddressSurface = true
    static let usesRootSpaceAtmosphere = true
    static let usesInsetLiftedPageSurface = true
    static let inheritsWindowTransparencyPreference = true
    static let addressFillsAvailableToolbarWidth = true
    static let destinationUsesDedicatedPrimaryAction = true
    static let destinationMenuIndicatorIsTrailing = true
    static let destinationUsesCustomSpacePicker = true
    static let destinationSpacePickerUsesSharedArtwork = true
    static let alignsNativeWindowControlsToToolbar = true
    static let openActionAlwaysEntersDestinationSpace = true
    static let spacePickerSelectionPromotesDirectly = true
    static let openActionRequiresLoadedPage = false
    static let usesExactSceneDismissal = true

    static func destinationTitle(spaceName: String) -> String {
        String(localized: "Open in \(spaceName)")
    }
}
