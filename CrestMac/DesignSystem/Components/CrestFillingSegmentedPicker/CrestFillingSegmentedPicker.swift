import AppKit
import SwiftUI

/// A segmented choice that spans the width it is given, its segments sharing
/// it equally, so a row holding only the choice has no empty room beside it.
/// The Mac's segmented picker keeps its own width whatever room it has, so
/// this is the system's segmented control told to fill.
struct CrestFillingSegmentedPicker<Choice: Hashable>: View {
    let title: LocalizedStringKey
    let choices: [Choice]
    @Binding var selection: Choice
    let label: (Choice) -> String

    var body: some View {
        CrestFillingSegmentedControl(
            labels: choices.map(label),
            selectedIndex: Binding(
                get: { choices.firstIndex(of: selection) ?? 0 },
                set: { if choices.indices.contains($0) { selection = choices[$0] } })
        )
        .frame(maxWidth: .infinity)
        .accessibilityLabel(Text(title))
    }
}

/// The system's segmented control, its segments filling its width.
private struct CrestFillingSegmentedControl: NSViewRepresentable {
    let labels: [String]
    @Binding var selectedIndex: Int

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: labels, trackingMode: .selectOne, target: context.coordinator,
            action: #selector(Coordinator.changed(_:)))
        control.segmentDistribution = .fillEqually
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selectedIndex = $selectedIndex
        if control.segmentCount != labels.count {
            control.segmentCount = labels.count
        }
        for (index, label) in labels.enumerated() where control.label(forSegment: index) != label {
            control.setLabel(label, forSegment: index)
        }
        if control.selectedSegment != selectedIndex {
            control.selectedSegment = selectedIndex
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedIndex: $selectedIndex)
    }

    /// Hands the segment the person chose back to the binding.
    final class Coordinator: NSObject {
        var selectedIndex: Binding<Int>

        init(selectedIndex: Binding<Int>) {
            self.selectedIndex = selectedIndex
        }

        @objc func changed(_ control: NSSegmentedControl) {
            selectedIndex.wrappedValue = control.selectedSegment
        }
    }
}
