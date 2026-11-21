import SwiftUI

/// A slider whose track shows what it does, so it needs no label on screen:
/// the colors it runs through from its start to its end, set into the
/// popover, under a thumb that wears the color it stands at. Pressing
/// anywhere on the track moves the thumb there and drags it on. Its title is
/// its name to VoiceOver and on hover. The color popover's brightness, and a
/// Space background's texture.
struct CrestColorSlider: View {
    // MARK: - Variables

    let title: LocalizedStringResource
    /// Where the thumb stands, from 0 to 1.
    @Binding var value: Double
    /// The colors along the track, evenly spaced from start to end.
    let track: [BrandColor]
    /// The color the thumb wears.
    let thumb: BrandColor
    /// Whether the track shows grain coming in from its start to its end,
    /// for a slider that sets texture.
    var showsGrain = false

    @State private var isDragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - Actions - Drawing

    var body: some View {
        GeometryReader { geometry in
            let inset = CrestColorSliderMetrics.thumb / 2
            let span = max(geometry.size.width - 2 * inset, 1)
            ZStack(alignment: .leading) {
                LinearGradient(colors: track.map(\.color), startPoint: .leading, endPoint: .trailing)
                    .overlay {
                        if showsGrain {
                            CrestGrain(style: .fine)
                                .blendMode(reduceTransparency ? .normal : .softLight)
                                .opacity(CrestGrainMetrics.fullOpacity)
                                .mask(
                                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing))
                        }
                    }
                    .crestColorInset(Capsule(), rim: CrestColorSliderMetrics.rim)
                    .frame(height: CrestColorSliderMetrics.track)
                Circle()
                    .fill(thumb.color)
                    .overlay { Circle().strokeBorder(.white, lineWidth: 3) }
                    .shadow(
                        color: .black.opacity(isDragging ? 0.4 : 0.3), radius: isDragging ? 6 : 3,
                        y: isDragging ? 3 : 1
                    )
                    .frame(width: CrestColorSliderMetrics.thumb, height: CrestColorSliderMetrics.thumb)
                    .scaleEffect(isDragging ? CrestColorSliderMetrics.liftedScale : 1)
                    .animation(CrestMotion.press.unlessReducingMotion(reduceMotion), value: isDragging)
                    .position(x: inset + min(max(value, 0), 1) * span, y: geometry.size.height / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        value = min(max((drag.location.x - inset) / span, 0), 1)
                    }
                    .onEnded { _ in isDragging = false })
        }
        .frame(height: CrestColorSliderMetrics.height)
        .help(Text(title))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
        .accessibilityAdjustableAction { direction in
            if direction == .increment {
                value = min(value + CrestColorSliderMetrics.accessibilityStep, 1)
            } else if direction == .decrement {
                value = max(value - CrestColorSliderMetrics.accessibilityStep, 0)
            }
        }
    }
}

enum CrestColorSliderMetrics {
    /// How wide the recess round the track is.
    static let rim: CGFloat = 2.5
    static let height: CGFloat = 28
    static let track: CGFloat = 14
    static let thumb: CGFloat = 22
    /// How much the thumb grows while it is dragged.
    static let liftedScale: CGFloat = 1.12
    /// How far one swipe of an adjustable action moves the thumb.
    static let accessibilityStep = 0.05
}

#if DEBUG
    #Preview("Color sliders") {
        @Previewable @State var value = 0.45
        let color = CrestColorWheelPoint(hue: 0.6, vibrancy: 0.7, lightness: value)
        CrestColorSlider(
            title: "Brightness", value: $value, track: (0...8).map { color.with(lightness: Double($0) / 8).color },
            thumb: color.color
        )
        .padding()
        .frame(width: 320)
    }
#endif
