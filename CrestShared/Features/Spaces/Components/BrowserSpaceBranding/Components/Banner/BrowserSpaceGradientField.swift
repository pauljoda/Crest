import SwiftUI

/// A Space's colors as its gradient: along a line, out from the middle, or
/// around it, as its fill runs. One color fills it evenly.
struct BrowserSpaceGradientField: View {
    let fill: CrestColorFill

    var body: some View {
        Rectangle().fill(fill.style)
    }
}

#if DEBUG
    #Preview("Gradient angle") {
        @Previewable @State var angle = 45.0
        VStack {
            BrowserSpaceGradientField(fill: CrestColorFill([.indigo, .sky, .sand], degrees: angle))
                .frame(height: 280)
            Slider(value: $angle, in: 0...360)
        }.padding().frame(width: 360)
    }
#endif
