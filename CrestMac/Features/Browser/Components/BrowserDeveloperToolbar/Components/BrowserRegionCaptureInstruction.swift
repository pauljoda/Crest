import SwiftUI

struct BrowserRegionCaptureInstruction: View {
    var body: some View {
        Label(
            "Drag to capture a portion of this page",
            systemImage: "camera.viewfinder"
        )
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 18)
        .frame(height: 42)
        .background(.regularMaterial, in: .capsule)
        .padding(.bottom, 28)
        .allowsHitTesting(false)
    }
}

#Preview("Region Capture Instruction") {
    BrowserRegionCaptureInstruction()
        .padding()
}
