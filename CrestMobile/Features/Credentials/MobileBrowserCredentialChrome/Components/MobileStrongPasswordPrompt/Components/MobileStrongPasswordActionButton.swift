import SwiftUI

struct MobileStrongPasswordActionButton: View {
    let isWorking: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isWorking {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityLabel("Creating strong password")
            } else {
                Label(
                    "Use Strong Password",
                    systemImage: "key.horizontal.fill"
                )
                .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .disabled(isWorking)
    }
}
