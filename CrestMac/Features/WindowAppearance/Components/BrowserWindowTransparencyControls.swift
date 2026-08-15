import SwiftUI

struct BrowserWindowTransparencyControls: View {
    @Environment(BrowserWindowTransparencyStore.self) private var transparency

    var body: some View {
        @Bindable var transparency = transparency
        Toggle(
            "Focused window transparency",
            isOn: $transparency.isEnabled
        )

        BrowserWindowTransparencyStrengthControl(
            strength: $transparency.strength,
            isEnabled: transparency.isEnabled
        )
    }
}

#Preview("Transparency controls") {
    Form {
        BrowserWindowTransparencyControls()
    }
    .environment(BrowserWindowTransparencyPreviewFixture.makeStore())
    .frame(width: 480)
}
