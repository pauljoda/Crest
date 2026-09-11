import SwiftUI

/// How a slider names its live value.
struct CrestSettingSliderReadout: Sendable {
    let label: @Sendable (Double) -> String

    init(label: @escaping @Sendable (Double) -> String) {
        self.label = label
    }

    /// A plain percentage of the control's range.
    static let percent = CrestSettingSliderReadout {
        $0.formatted(.percent.precision(.fractionLength(0)))
    }

    /// A percentage whose ends have names of their own, as "Subtle" and
    /// "Opaque" do for a folder's color.
    static func percent(zero: LocalizedStringResource, full: LocalizedStringResource) -> Self {
        CrestSettingSliderReadout { value in
            if value <= 0 { return String(localized: zero) }
            if value >= 1 { return String(localized: full) }
            return value.formatted(.percent.precision(.fractionLength(0)))
        }
    }

    /// A point measurement, such as the window border, whose zero is a word.
    static func points(zero: LocalizedStringResource) -> Self {
        CrestSettingSliderReadout { value in
            value <= 0 ? String(localized: zero) : String(localized: "\(Int(value.rounded())) pt")
        }
    }

    /// A multiplier reported as the percentage of normal size it produces.
    static let multiplier = CrestSettingSliderReadout {
        $0.formatted(.percent.precision(.fractionLength(0)))
    }
}

/// The one slider presentation Crest's settings use: the title on the leading
/// edge, and on the trailing edge a fixed-width track with its live readout.
///
/// The readout does the work end labels used to: it names the zero point
/// ("Borderless", "Square") and reports the exact value everywhere else, so a
/// slider row is one line tall like every other row.
struct CrestSettingSlider: View {
    private let title: LocalizedStringKey
    private let value: CrestSettingValue<Double>
    private let range: ClosedRange<Double>
    private let step: Double?
    private let readout: CrestSettingSliderReadout
    private let identifier: String?

    init(
        _ title: LocalizedStringKey,
        value: CrestSettingValue<Double>,
        range: ClosedRange<Double> = 0...1,
        step: Double? = nil,
        readout: CrestSettingSliderReadout = .percent,
        identifier: String? = nil
    ) {
        self.title = title
        self.value = value
        self.range = range
        self.step = step
        self.readout = readout
        self.identifier = identifier
    }

    var body: some View {
        CrestSettingRow(title, setting: value.resettable(title)) {
            HStack(spacing: CrestSettingRowMetrics.controlSpacing) {
                slider
                    .frame(width: CrestSettingRowMetrics.sliderWidth)
                Text(valueLabel)
                    .font(CrestTypography.metadata)
                    .foregroundStyle(CrestColor.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(width: CrestSettingRowMetrics.readoutWidth, alignment: .trailing)
            }
        }
    }

    private var slider: some View {
        Group {
            if let step {
                Slider(value: value.binding, in: range, step: step) { Text(title) }
            } else {
                Slider(value: value.binding, in: range) { Text(title) }
            }
        }
        .labelsHidden()
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(valueLabel))
        .accessibilityIdentifier(identifier ?? "")
    }

    private var valueLabel: String { readout.label(value.wrappedValue) }
}
