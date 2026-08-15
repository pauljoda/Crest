struct BrowserPasswordSettingsLayout: Equatable {
    let showsCredentialPreferences: Bool
    let showsSavedPasswords: Bool
    let showsExportAction: Bool
    let showsManageAction: Bool

    static let macOSPage = BrowserPasswordSettingsLayout(
        showsCredentialPreferences: false,
        showsSavedPasswords: true,
        showsExportAction: true,
        showsManageAction: false
    )

    static let mobilePage = BrowserPasswordSettingsLayout(
        showsCredentialPreferences: true,
        showsSavedPasswords: false,
        showsExportAction: false,
        showsManageAction: true
    )
}
