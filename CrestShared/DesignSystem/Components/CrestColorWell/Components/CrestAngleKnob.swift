import SwiftUI

/// A dial for an angle: a ring with a handle the person drags around it and
/// an arrow from the center pointing the way the angle runs, 0° toward the
/// right and 90° down, as a gradient's angle runs. The angle settles on the
/// nearest eighth of a turn when the handle passes close to one, with a tick
/// on a trackpad or phone that gives one, and steps by `step` from the
/// keyboard or an assistive device. The handle lifts while it turns.
struct CrestAngleKnob: View {
    // MARK: - Variables

    @Binding var degrees: Double
    var diameter = CrestAngleKnobMetrics.diameter
    var step = CrestAngleKnobMetrics.step

    /// Whether a press is turning the dial.
    @State private var isTurning = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var radius: CGFloat { diameter / 2 }

    // MARK: - Actions - Drawing

    var body: some View {
        ZStack {
            Circle()
                .fill(.quaternary)
            Circle()
                .strokeBorder(CrestBrandTheme.line, lineWidth: CrestLayout.hairline)
            ForEach(0..<8, id: \.self) { index in
                Capsule()
                    .fill(.tertiary)
                    .frame(width: CrestAngleKnobMetrics.tickWidth, height: CrestAngleKnobMetrics.tickLength)
                    .offset(y: -radius + CrestAngleKnobMetrics.tickInset)
                    .rotationEffect(.degrees(Double(index) * 45))
            }
            Image(systemName: "arrow.right")
                .font(.system(size: diameter * CrestAngleKnobMetrics.arrowScale, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(degrees))
            Circle()
                .fill(.white)
                .overlay { Circle().strokeBorder(CrestBrandTheme.line, lineWidth: CrestLayout.hairline) }
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                .frame(width: CrestAngleKnobMetrics.handle, height: CrestAngleKnobMetrics.handle)
                .scaleEffect(isTurning ? CrestAngleKnobMetrics.turningScale : 1)
                .offset(handleOffset)
                .animation(CrestMotion.press.unlessReducingMotion(reduceMotion), value: isTurning)
        }
        .frame(width: diameter, height: diameter)
        .opacity(isEnabled ? 1 : CrestOpacity.disabled)
        .contentShape(.circle)
        .gesture(turn)
        .sensoryFeedback(.alignment, trigger: degrees) { old, new in
            old != new && new.truncatingRemainder(dividingBy: 45) == 0
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Direction"))
        .accessibilityValue(Text("\(Int(degrees.rounded())) degrees"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: degrees = Self.normalized(degrees + step)
            case .decrement: degrees = Self.normalized(degrees - step)
            @unknown default: break
            }
        }
        .help(Text("Direction"))
    }

    /// Where the handle sits on the ring for the angle.
    private var handleOffset: CGSize {
        let ring = radius - CrestAngleKnobMetrics.handle / 2 - CrestAngleKnobMetrics.handleInset
        let radians = degrees * .pi / 180
        return CGSize(width: ring * cos(radians), height: ring * sin(radians))
    }

    // MARK: - Actions - Turning

    private var turn: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isTurning = true
                let x = value.location.x - radius
                let y = value.location.y - radius
                guard hypot(x, y) > CrestAngleKnobMetrics.deadZone else { return }
                degrees = Self.settled(Self.normalized(atan2(y, x) * 180 / .pi))
            }
            .onEnded { _ in isTurning = false }
    }

    /// `degrees` within one turn, from 0 up to 360.
    static func normalized(_ degrees: Double) -> Double {
        let turned = degrees.truncatingRemainder(dividingBy: 360)
        return turned < 0 ? turned + 360 : turned
    }

    /// `degrees` on the nearest eighth of a turn when it is within reach of
    /// one, and otherwise on the nearest whole degree.
    static func settled(_ degrees: Double) -> Double {
        let eighth = (degrees / 45).rounded() * 45
        let settled = abs(degrees - eighth) <= CrestAngleKnobMetrics.settleReach ? eighth : degrees.rounded()
        return normalized(settled)
    }
}

enum CrestAngleKnobMetrics {
    static let diameter: CGFloat = 44
    static let handle: CGFloat = 12
    /// How much the handle grows while the dial turns.
    static let turningScale: CGFloat = 1.3
    static let handleInset: CGFloat = 2
    static let tickWidth: CGFloat = 1.5
    static let tickLength: CGFloat = 4
    static let tickInset: CGFloat = 4
    static let arrowScale: CGFloat = 0.3
    /// How close to the center a press may land before it turns the dial.
    static let deadZone: CGFloat = 4
    /// How close to an eighth of a turn the angle settles on it.
    static let settleReach = 4.0
    /// How far one step from the keyboard or an assistive device turns it.
    static let step = 15.0
}

#if DEBUG
    #Preview("Component") {
        @Previewable @State var degrees = 90.0
        CrestAngleKnob(degrees: $degrees).padding()
    }
#endif
