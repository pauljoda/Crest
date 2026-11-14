import CoreGraphics

/// How densely the sidebar draws its rows and pins, from the person's tab
/// size.
///
/// Rows and pins take the size in full, while their text and icons follow it
/// half as far, so a thin row loses the room around its title before the
/// title itself gets hard to read. The room between rows and between pins
/// follows the person's spacing.
struct BrowserSidebarDensity: Equatable, Sendable {
    // MARK: - Static Variables

    static let scaleRange: ClosedRange<Double> = 0.6...1.4
    /// The steps the tab size moves in.
    static let scaleStep = 0.1
    /// How far text and icons follow the size, as a share of how far rows do.
    private static let contentResponse = 0.5
    /// The sizes the presets before the slider stored, which sit between its
    /// steps, and the steps that now carry their names.
    private static let presetSteps: [(stored: Double, step: Double)] = [(0.85, 0.8), (1.15, 1.2)]
    private static let pointerBodySize: CGFloat = 13
    private static let touchBodySize: CGFloat = 17
    private static let minimumTouchTarget: CGFloat = 44
    private static let minimumPointerTarget: CGFloat = 24
    private static let minimumPointerPinHeight: CGFloat = 32
    private static let basePinHeight: CGFloat = 47
    private static let basePinWidth: CGFloat = 36
    private static let basePinSpacing: CGFloat = 8
    private static let minimumSpacing: CGFloat = 2

    // MARK: - Variables

    /// The density the person chose: their tab size at their spacing.
    @MainActor static var current: BrowserSidebarDensity {
        let appearance = BrowserDeviceAppearanceStore.shared
        return BrowserSidebarDensity(appearance.tabScale, spacing: appearance.sidebarSpacing)
    }

    /// The setting as stored, before it is held to `scaleRange`.
    let value: Double
    /// The room kept between rows and between pins.
    let spacing: BrowserSidebarSpacing

    /// The setting held to `scaleRange`, or 1 when it is not a number: the
    /// factor rows and pins take.
    var scale: Double {
        value.isFinite ? min(max(value, Self.scaleRange.lowerBound), Self.scaleRange.upperBound) : 1
    }

    /// The factor text and icons take, which moves half as far from 1 as
    /// ``scale``.
    var contentScale: Double {
        1 + (scale - 1) * Self.contentResponse
    }

    /// The space kept between pinned tiles, at this density, never so
    /// little that two tiles touch.
    var pinSpacing: Double {
        Double(spacing.gap(Self.basePinSpacing * scale, minimum: Self.minimumSpacing))
    }

    // MARK: - Initializers

    init(_ value: Double, spacing: BrowserSidebarSpacing = .standard) {
        self.value = value
        self.spacing = spacing
    }

    // MARK: - Actions - Stored sizes

    /// The size `stored` reads as: the step that took the name of a preset
    /// the person chose before the slider, or else `stored` itself.
    static func stepped(_ stored: Double) -> Double {
        presetSteps.first { abs($0.stored - stored) < 0.005 }?.step ?? stored
    }

    // MARK: - Actions - Layout

    static func bodySize(touch: Bool) -> CGFloat {
        touch ? touchBodySize : pointerBodySize
    }

    func rowHeight(base: CGFloat, touch: Bool) -> CGFloat {
        max(touch ? Self.minimumTouchTarget : Self.minimumPointerTarget, base * scale)
    }

    /// The space kept between rows: the designed gap at this spacing, and
    /// never less than borders need to stay apart.
    func rowSeparation(hasBorders: Bool = false) -> Double {
        let gap = Double(spacing.gap(Self.minimumSpacing))
        return hasBorders ? max(Self.minimumSpacing, gap) : gap
    }

    func pinHeight(touch: Bool) -> Double {
        max(touch ? Self.minimumTouchTarget : Self.minimumPointerPinHeight, Self.basePinHeight * scale)
    }

    func pinMinimumWidth(touch: Bool) -> Double {
        max(touch ? Self.minimumTouchTarget : Self.minimumPointerTarget, Self.basePinWidth * scale)
    }
}
