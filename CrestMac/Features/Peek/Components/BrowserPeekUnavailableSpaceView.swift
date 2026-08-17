import SwiftUI

struct BrowserPeekUnavailableSpaceView: View {
    let dismiss: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Peek Unavailable", systemImage: "eye.slash")
        } description: {
            Text("The Space that opened this Peek is no longer available.")
        } actions: {
            Button("Close Peek", action: dismiss)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
