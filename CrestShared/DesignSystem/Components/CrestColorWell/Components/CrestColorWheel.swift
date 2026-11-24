import SwiftUI

/// Every hue round the wheel and every vibrancy out from its gray center,
/// at the chosen color's lightness, under a fine grid of dots, with a handle
/// for each of a fill's colors. Pressing a handle chooses it and dragging it
/// moves it, lifted under the pointer and held within the rim, keeping its
/// lightness; linked, the rest orbit with it. Pressing anywhere else springs
/// the chosen handle there and drags it on. Handles pop in and out as colors
/// come and go.
struct CrestColorWheel: View {
    // MARK: - Variables

    @Binding var fill: CrestColorFill
    @Binding var selection: Int
    @Binding var stops: CrestColorStops
    /// Whether moving the chosen handle moves the rest with it.
    let isLinked: Bool
    /// Whether a press is moving the chosen handle.
    @State private var isDragging = false
    /// Whether the press under way began on the open wheel, so its first move
    /// springs the handle there.
    @State private var springsToPress = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Actions - Drawing

    var body: some View {
        GeometryReader { geometry in
            let wheel = Self.wheel(in: geometry.size)
            ZStack(alignment: .topLeading) {
                CrestColorWheelSurface(step: CrestColorWheelImage.step(of: chosen.lightness))
                    .equatable()
                    .frame(width: wheel.width, height: wheel.height)
                    .offset(x: wheel.minX, y: wheel.minY)
                ForEach(Array(zip(stops.ids(of: fill), fill.colors).enumerated()), id: \.element.0) { index, element in
                    handle(element.1, isChosen: index == selection)
                        .position(location(of: CrestColorWheelPoint(element.1), in: wheel))
                        .zIndex(index == selection ? 1 : 0)
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                        .accessibilityElement()
                        .accessibilityLabel(Text("Color \(index + 1)"))
                        .accessibilityAddTraits(index == selection ? .isSelected : [])
                        .accessibilityAction { selection = index }
                        .accessibilityAdjustableAction { direction in
                            turn(
                                index,
                                by: direction == .increment
                                    ? CrestColorWheelMetrics.turnStep : -CrestColorWheelMetrics.turnStep)
                        }
                }
            }
            .contentShape(.rect)
            .gesture(drag(in: wheel))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Colors"))
    }

    private func handle(_ color: BrandColor, isChosen: Bool) -> some View {
        let diameter = isChosen ? CrestColorWheelMetrics.chosenHandle : CrestColorWheelMetrics.handle
        let lifted = isChosen && isDragging
        return Circle()
            .fill(color.color)
            .overlay { Circle().strokeBorder(.white, lineWidth: isChosen ? 4 : 3) }
            .crestElevation(lifted ? .heldHandle : .handle)
            .frame(width: diameter, height: diameter)
            .scaleEffect(lifted ? CrestColorWheelMetrics.liftedScale : 1)
            .animation(CrestMotion.selection.unlessReducingMotion(reduceMotion), value: isChosen)
            .animation(CrestMotion.press.unlessReducingMotion(reduceMotion), value: lifted)
    }

    // MARK: - Actions - Placing

    /// The chosen color as the wheel reads it, whose lightness the wheel is
    /// drawn at.
    private var chosen: CrestColorWheelPoint {
        CrestColorWheelPoint(fill.colors[min(selection, fill.colors.count - 1)])
    }

    /// The largest circle `size` holds, centered, inset so a handle on the
    /// rim stays whole.
    private static func wheel(in size: CGSize) -> CGRect {
        let side = max(min(size.width, size.height) - CrestColorWheelMetrics.chosenHandle, 0)
        return CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
    }

    private func location(of point: CrestColorWheelPoint, in wheel: CGRect) -> CGPoint {
        let position = point.position
        return CGPoint(x: wheel.midX + position.x * wheel.width / 2, y: wheel.midY + position.y * wheel.height / 2)
    }

    /// The color under `location`, at the chosen color's lightness; a
    /// location past the rim takes the rim.
    private func point(at location: CGPoint, in wheel: CGRect) -> CrestColorWheelPoint {
        let radius = max(wheel.width / 2, 1)
        return CrestColorWheelPoint(
            position: CGPoint(x: (location.x - wheel.midX) / radius, y: (location.y - wheel.midY) / radius),
            lightness: chosen.lightness)
    }

    /// A press near a handle chooses it and drags it; a press anywhere else
    /// springs the chosen handle to it and drags it on from there.
    private func drag(in wheel: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDragging {
                    if let near = nearestHandle(to: value.startLocation, in: wheel) {
                        withAnimation(CrestMotion.selection.unlessReducingMotion(reduceMotion)) { selection = near }
                        springsToPress = false
                    } else {
                        springsToPress = true
                    }
                    isDragging = true
                }
                let color = point(at: value.location, in: wheel).color
                if springsToPress {
                    springsToPress = false
                    withAnimation(CrestMotion.colorPop.unlessReducingMotion(reduceMotion)) {
                        stops.move(color, at: selection, in: &fill, linked: isLinked)
                    }
                } else {
                    stops.move(color, at: selection, in: &fill, linked: isLinked)
                }
            }
            .onEnded { _ in isDragging = false }
    }

    /// Turns color `index` round the wheel by `turn` of a full turn, keeping
    /// its vibrancy and lightness, as an assistive device adjusts it; linked,
    /// the rest turn with it.
    private func turn(_ index: Int, by turn: Double) {
        guard fill.colors.indices.contains(index) else { return }
        selection = index
        let point = CrestColorWheelPoint(fill.colors[index])
        let turned = CrestColorWheelPoint(
            hue: (point.hue + turn + 1).truncatingRemainder(dividingBy: 1), vibrancy: point.vibrancy,
            lightness: point.lightness)
        stops.move(turned.color, at: index, in: &fill, linked: isLinked)
    }

    private func nearestHandle(to press: CGPoint, in wheel: CGRect) -> Int? {
        let distance = { (index: Int) in
            let handle = location(of: CrestColorWheelPoint(fill.colors[index]), in: wheel)
            return hypot(handle.x - press.x, handle.y - press.y)
        }
        return fill.colors.indices
            .filter { distance($0) < CrestColorWheelMetrics.reach }
            .min { distance($0) < distance($1) }
    }
}

/// The wheel under the handles: its hues and vibrancies at one step of
/// lightness, drawn from the rule a handle's color comes from, under a fine
/// grid of dots, set into the popover, rendered apart from the handles so
/// moving one redraws nothing beneath it.
struct CrestColorWheelSurface: View, Equatable {
    /// The step of lightness the wheel shows.
    let step: Int

    var body: some View {
        Image(decorative: CrestColorWheelImage.image(step: step), scale: 1)
            .resizable()
            .interpolation(.high)
            .overlay {
                Canvas { context, size in
                    let spacing = CrestColorWheelMetrics.gridSpacing
                    var dots = Path()
                    for x in stride(from: spacing / 2, to: size.width, by: spacing) {
                        for y in stride(from: spacing / 2, to: size.height, by: spacing) {
                            dots.addEllipse(in: CGRect(x: x - 0.6, y: y - 0.6, width: 1.2, height: 1.2))
                        }
                    }
                    context.fill(dots, with: .color(.white.opacity(0.3)))
                }
                .clipShape(.circle)
            }
            .drawingGroup()
            .crestColorInset(Circle())
            .allowsHitTesting(false)
    }
}

enum CrestColorWheelMetrics {
    static let gridSpacing: CGFloat = 9
    static let handle: CGFloat = 26
    static let chosenHandle: CGFloat = 36
    /// How much the chosen handle grows while it is dragged.
    static let liftedScale: CGFloat = 1.12
    /// How close a press must land to a handle to choose it.
    static let reach: CGFloat = 22
    /// How far one step of an assistive device turns a color round the
    /// wheel, as a share of a full turn.
    static let turnStep = 1.0 / 36
}
