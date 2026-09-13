import SwiftUI

struct BrowserSettingsTabContent {
    let present: @MainActor (BrowserTabRuntimeAssignment) -> Void

    func makeView(_ runtime: BrowserNativeTabRuntime) -> some View {
        Button("Open Settings", systemImage: "gearshape") {
            present(runtime.assignment)
        }
        .buttonStyle(.borderedProminent)
    }
}
