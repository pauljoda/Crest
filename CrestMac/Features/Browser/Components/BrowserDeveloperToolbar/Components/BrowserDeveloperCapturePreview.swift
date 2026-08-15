import SwiftUI

struct BrowserDeveloperCapturePreview: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.indigo, .purple, .cyan],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(height: 112)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.black.opacity(0.72))
                    .padding(22)
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
            }
            .accessibilityHidden(true)
    }
}

#Preview("Developer Capture Preview") {
    BrowserDeveloperCapturePreview()
        .padding()
        .frame(width: 260)
}
