import SwiftUI

/// What a color well opens: the color wheel with a handle for each of the
/// fill's colors, then one row of even controls under it, minus and plus in
/// the middle and, once there are two or more colors, the gradient's
/// direction at the leading end and the link at the trailing end, fading in;
/// then the chosen color's brightness, and the texture where the well has
/// one, then the spectrum, a hue for each
/// step round the wheel, which sets the chosen handle. Every gradient runs
/// straight, toward its direction. Nothing but the color: strength, texture and pattern stay
/// with the editor the well sits in. The popover edits its own copy, which
/// reaches the well's fill at most `commitInterval` apart, and further apart
/// while the app is still drawing the last change, so the controls keep up
/// with the pointer however much the fill redraws behind them, a whole
/// browser window included.
struct CrestColorPopover: View {
    // MARK: - Static Variables

    /// The spectrum's colors: hues evenly round the color wheel as the eye sees
    /// them, each at the same soft chroma, a UI color rather than a vivid
    /// one, and at a lightness leaning toward where its hue is most vivid,
    /// so the yellows stay clear of mustard and the blues aren't washed out.
    /// The spectrum's names, one for each hue in order from its red.
    private static let spectrumNames: [LocalizedStringResource] = [
        "Red", "Orange", "Yellow", "Lime", "Green", "Mint", "Teal", "Sky", "Blue", "Violet", "Purple", "Pink",
    ]

    private static let spectrum: [BrandColor] = (0..<CrestColorPopoverMetrics.spectrumHues).map { step in
        let metrics = CrestColorPopoverMetrics.self
        let degrees = metrics.spectrumFirstHue + Double(step) * 360 / Double(metrics.spectrumHues)
        let cusp = CrestPerceptualColor.cuspLightness(degrees: degrees)
        let lightness = metrics.spectrumLightness + metrics.spectrumCuspPull * (cusp - metrics.spectrumLightness)
        return CrestPerceptualColor(lightness: lightness, chroma: metrics.spectrumChroma, hue: degrees / 360).color
    }

    // MARK: - Variables

    @Binding var fill: CrestColorFill
    /// How strongly grain lies over the colors, for a well whose colors are
    /// a surface's, such as a Space's background; nil for one without.
    var texture: Binding<Double>?
    /// The popover's copy of the fill, which its controls change.
    @State private var draft: CrestColorFill
    @State private var selection = 0
    @State private var stops = CrestColorStops()
    /// Whether moving one color shifts the rest with it, keeping the
    /// gradient's shape. Every popover opens linked.
    @State private var isLinked = true
    /// The pending hand-over of the copy to the well's fill.
    @State private var commit: Task<Void, Never>?
    /// How long the copy waits to reach the well's fill: `commitInterval`
    /// while the app keeps up, longer while it is still drawing the last
    /// change.
    @State private var commitPace = CrestColorPopoverMetrics.commitInterval
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Initializers

    init(fill: Binding<CrestColorFill>, texture: Binding<Double>? = nil) {
        _fill = fill
        self.texture = texture
        _draft = State(initialValue: fill.wrappedValue)
    }

    // MARK: - Actions - Drawing

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            VStack(spacing: CrestSpacing.small) {
                // Where the screen leaves the popover less room than it asks
                // for, as on a phone, the wheel gives up the difference and
                // everything under it keeps its size.
                CrestColorWheel(fill: $draft, selection: $selection, stops: $stops, isLinked: isLinked)
                    .frame(
                        minHeight: CrestColorPopoverMetrics.smallestWheelHeight,
                        idealHeight: CrestColorPopoverMetrics.wheelHeight,
                        maxHeight: CrestColorPopoverMetrics.wheelHeight)
                controls
            }
            brightness
            if let texture {
                CrestColorSlider(
                    title: "Texture", value: texture, track: [draft.colors[0], draft.colors[0]], thumb: draft.colors[0],
                    showsGrain: true)
            }
            spectrum
        }
        .padding(CrestColorPopoverMetrics.inset)
        // Narrower where the popover opens beside a well on a phone, the
        // wheel and the rows under it taking the width there is.
        .frame(
            minWidth: CrestColorPopoverMetrics.smallestWidth, idealWidth: CrestColorPopoverMetrics.width,
            maxWidth: CrestColorPopoverMetrics.width
        )
        // The popover takes its new size in one step rather than animating
        // its frame against the content, so nothing in it moves as it grows.
        .modifier(CrestPlatformInstantPopoverResizing())
        .animation(CrestMotion.selection.unlessReducingMotion(reduceMotion), value: draft.isGradient)
        .onAppear {
            stops.adopt(draft)
            // Every gradient runs straight; one of another kind takes a line.
            if draft.isGradient, draft.kind != .linear { draft.kind = .linear }
        }
        .onChange(of: draft) { _, _ in scheduleCommit() }
        .onChange(of: fill) { _, outside in
            guard commit == nil, outside != draft else { return }
            draft = outside
            stops.adopt(outside)
            stops.releaseShape()
        }
        .onChange(of: draft.colors.count) { _, count in selection = min(selection, count - 1) }
        .onChange(of: isLinked) { _, _ in stops.releaseShape() }
        .onDisappear(perform: commitNow)
    }

    /// The chosen color as the wheel reads it.
    private var chosen: CrestColorWheelPoint {
        CrestColorWheelPoint(draft.colors[chosenIndex])
    }

    private var chosenIndex: Int {
        min(selection, draft.colors.count - 1)
    }

    /// The chosen color's brightness, from black to white, over a track of
    /// the colors it runs through. Its vibrancy is its distance from the
    /// wheel's center.
    private var brightness: some View {
        let color = chosen
        let steps = CrestColorPopoverMetrics.trackSteps
        let edge = CrestColorWheelPoint.edgeLightness
        return CrestColorSlider(
            title: "Brightness",
            value: Binding(
                get: { chosen.lightness },
                set: { set(chosen.with(lightness: min(max($0, edge), 1 - edge))) }),
            track: (0...steps).map { color.with(lightness: Double($0) / Double(steps)).color },
            thumb: color.color)
    }

    /// The row under the wheel, every control the same size: the
    /// gradient's direction, minus and plus in the middle, and the link.
    private var controls: some View {
        ZStack {
            CrestColorCountControls(fill: $draft, selection: $selection, stops: $stops)
            HStack {
                if draft.isGradient {
                    CrestAngleKnob(degrees: $draft.degrees, diameter: CrestColorPopoverMetrics.control.height)
                        .transition(.scale(scale: CrestMotion.entranceScale).combined(with: .opacity))
                }
                Spacer(minLength: 0)
                if draft.isGradient {
                    CrestColorLinkToggle(isLinked: $isLinked)
                        .transition(.scale(scale: CrestMotion.entranceScale).combined(with: .opacity))
                }
            }
        }
        .frame(height: CrestColorPopoverMetrics.control.height)
    }

    /// The spectrum: a named hue every step round the wheel, each setting
    /// the chosen handle, which the wheel and Brightness then tune.
    /// One row where the popover is wide enough for every hue, two of half
    /// as many where it is narrower, as beside a well on a phone.
    private var spectrum: some View {
        let hues = Array(zip(Self.spectrum, Self.spectrumNames))
        let half = hues.count / 2
        return ViewThatFits(in: .horizontal) {
            spectrumRow(hues[...])
            VStack(spacing: CrestSpacing.extraSmall) {
                spectrumRow(hues[..<half])
                spectrumRow(hues[half...])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Spectrum"))
    }

    private func spectrumRow(_ hues: ArraySlice<(BrandColor, LocalizedStringResource)>) -> some View {
        HStack(spacing: 0) {
            ForEach(hues, id: \.0) { color, name in
                CrestSelectableCard(
                    isSelected: draft.colors[chosenIndex].matches(color),
                    accessibilityLabel: Text(name), density: .swatch, tint: nil
                ) {
                    withAnimation(CrestMotion.colorPop.unlessReducingMotion(reduceMotion)) {
                        stops.move(color, at: chosenIndex, in: &draft, linked: isLinked)
                    }
                } content: {
                    Circle()
                        .fill(color.color)
                        .overlay { Circle().strokeBorder(CrestBrandTheme.line, lineWidth: CrestLayout.hairline) }
                        .frame(
                            width: CrestColorPopoverMetrics.swatchDiameter,
                            height: CrestColorPopoverMetrics.swatchDiameter)
                }
                .help(Text(name))
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Mutators

    /// Gives the chosen handle `point`'s color, which makes it the person's,
    /// moving the rest with it while linked.
    private func set(_ point: CrestColorWheelPoint) {
        stops.move(point.color, at: chosenIndex, in: &draft, linked: isLinked)
    }

    /// Hands the copy to the well's fill once the pace has passed, with
    /// whatever it holds by then. Waking late means the app is still drawing
    /// the last hand-over, so the next waits that much longer, up to
    /// `slowestCommitInterval`; waking on time quickens the pace again.
    private func scheduleCommit() {
        guard commit == nil else { return }
        let pace = commitPace
        commit = Task { @MainActor in
            let clock = ContinuousClock()
            let asked = clock.now
            try? await Task.sleep(for: pace)
            guard !Task.isCancelled else { return }
            let late = asked.duration(to: clock.now) - pace
            commitPace =
                late > CrestColorPopoverMetrics.lateness
                ? min(pace + late, CrestColorPopoverMetrics.slowestCommitInterval)
                : max(pace - CrestColorPopoverMetrics.paceStep, CrestColorPopoverMetrics.commitInterval)
            commit = nil
            if fill != draft { fill = draft }
        }
    }

    /// Hands the copy to the well's fill now, as the popover closes.
    private func commitNow() {
        commit?.cancel()
        commit = nil
        if fill != draft { fill = draft }
    }
}

enum CrestColorPopoverMetrics {
    static let width: CGFloat = 320
    #if os(macOS)
        /// The room between the popover's edge and what it holds.
        static let inset = CrestSpacing.medium
    #else
        /// The room between the popover's edge and what it holds, more on a
        /// phone or iPad, whose popover corners are much rounder.
        static let inset = CrestSpacing.large
    #endif
    /// The narrowest the popover gets where the screen leaves it less room.
    static let smallestWidth: CGFloat = 260
    /// The wheel's room, as wide as the popover's content: its diameter and
    /// the chosen handle's overhang at the rim.
    static let wheelHeight: CGFloat = width - 2 * inset
    /// The least room the wheel shrinks to where the popover has to fit a
    /// smaller space.
    static let smallestWheelHeight: CGFloat = 120
    /// Every control in the row under the wheel.
    static let control = CGSize(width: 36, height: 32)
    /// A spectrum swatch, small enough that all of them fit the popover's
    /// width with the ring each draws around it.
    static let swatchDiameter: CGFloat = 16
    /// How many hues the spectrum shows, one every 30°, from a red.
    static let spectrumHues = 12
    static let spectrumFirstHue = 25.0
    /// The spectrum's OKLCH lightness and chroma, and how far each hue's
    /// lightness leans toward the lightness where it is most vivid.
    static let spectrumLightness = 0.70
    static let spectrumChroma = 0.12
    static let spectrumCuspPull = 0.4
    /// How many steps a slider's track blends between, enough for the turn
    /// of a brightness track from black through the color to white.
    static let trackSteps = 8
    /// The longest the well's fill trails the popover's copy, about two
    /// frames, so whatever the fill redraws keeps pace with the pointer
    /// without redrawing on every move.
    static let commitInterval = Duration.milliseconds(33)
    /// The longest the fill trails the copy while the app is busy drawing.
    static let slowestCommitInterval = Duration.milliseconds(120)
    /// How late a hand-over may wake before the pace slows, and how much an
    /// on-time one quickens it.
    static let lateness = Duration.milliseconds(8)
    static let paceStep = Duration.milliseconds(8)
}

#if DEBUG
    #Preview("Color popover") {
        @Previewable @State var fill = CrestColorFill([.indigo, .sky, .sand], kind: .linear, degrees: 90)
        CrestColorPopover(fill: $fill)
    }
#endif
