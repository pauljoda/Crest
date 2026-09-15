import SwiftUI

struct BrowserAdvancedSetupSection: View {
    let setupActions: [BrowserAdvancedSetupAction]

    var body: some View {
        Section("Setup", systemImage: "slider.horizontal.3") {
            ForEach(setupActions) { setupAction in
                BrowserAdvancedSetupActionButton(setupAction: setupAction)
            }
        }
    }
}
