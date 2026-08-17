import SwiftUI

struct MobilePasswordDataSections: View {
    @Bindable var model: MobilePasswordSettingsModel

    var body: some View {
        Group {
            if let selectedSpace = model.selectedSpace {
                if model.canRevealSelectedSpaceData {
                    MobilePasswordCredentialSection(model: model)

                    if let errorMessage = model.credentials.errorMessage {
                        Section {
                            Label(
                                errorMessage,
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(.red)
                        }
                    }

                    Section {
                        CrestFormFootnote(
                            "Only account and site metadata is shown here. Password values stay in the selected Space’s Data Protection Keychain and never enter Crest session or CloudKit records."
                        )
                    }
                } else {
                    BrowserSettingsPrivateSpaceAccessSection(
                        space: selectedSpace,
                        accessController: model.spaceAccess,
                        detail:
                            "Unlock this Space before viewing account and site metadata or changing its password settings."
                    )
                }
            }
        }
    }
}
