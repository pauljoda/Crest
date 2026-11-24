import SwiftUI

/// The touch shell's Autofill manager: passwords, codes, addresses and cards.
///
/// Everything this screen draws is ``BrowserAutofillSettingsPane``; what stays
/// here is the one thing only touch has — a sheet around the pane, with the search
/// field its list is filtered by and the Done button that closes it. The desktop puts
/// the same pane on a settings page and searches it from the window's own field.
struct MobilePasswordSettingsView: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            BrowserAutofillSettingsPane(
                browser: browser,
                spaceAccess: spaceAccess,
                layout: .mobileSheet,
                searchText: $searchText
            )
            .environment(\.browserCodeScanning, codeScanning)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search accounts or sites")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
        .presentationDetents([.large])
    }

    /// Set Up Code reads a QR code with the camera, where the device has one.
    private var codeScanning: BrowserCodeScanning {
        BrowserCodeScanning(scanWithCamera: MobileCodeCameraScanner.isAvailable ? { await MobileCodeCameraScanner.scan() } : nil)
    }
}
