import SwiftUI

/// A segmented choice that spans the width it is given, its segments sharing
/// it equally. The system's segmented picker already fills the room it has
/// on iPhone and iPad.
struct CrestFillingSegmentedPicker<Choice: Hashable>: View {
    let title: LocalizedStringKey
    let choices: [Choice]
    @Binding var selection: Choice
    let label: (Choice) -> String

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(choices, id: \.self) { choice in
                Text(verbatim: label(choice)).tag(choice)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)
    }
}
