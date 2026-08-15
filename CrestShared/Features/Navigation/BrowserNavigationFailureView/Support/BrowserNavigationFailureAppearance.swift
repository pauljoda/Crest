enum BrowserNavigationFailureAppearance {
    static func brandColor(
        for branding: BrowserSpaceBranding?
    ) -> BrowserSpaceBrandColor? {
        branding?.primaryColor
    }
}
