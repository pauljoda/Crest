import SwiftUI

/// Bindings normalize at the editing boundary, shared by setup drafts and live Spaces.
@MainActor
struct BrowserCrestStudioContext {
    let branding: Binding<SpaceBranding>
    let defaults: SpaceBranding
    var compact: Bool
    var previewBranding: SpaceBranding?
    var value: SpaceBranding { branding.wrappedValue }

    func preview(_ mutation: (inout SpaceBranding) -> Void) -> SpaceBranding {
        var candidate = previewBranding ?? value
        candidate.iconStyle = .layeredCrest
        mutation(&candidate)
        return candidate.normalized()
    }

    func crest<Value: Equatable>(_ path: WritableKeyPath<SpaceCrest, Value>) -> CrestSettingValue<Value> {
        CrestSettingValue(
            Binding(
                get: { value.crest[keyPath: path] },
                set: { next in
                    branding.editorUpdate {
                        $0.crest[keyPath: path] = next
                        $0.hasCustomAppearance = true
                    }
                }), default: defaults.crest[keyPath: path])
    }

    func setting<Value: Equatable>(_ path: WritableKeyPath<SpaceBranding, Value>) -> CrestSettingValue<Value> {
        CrestSettingValue(
            Binding(
                get: { value[keyPath: path] },
                set: { next in
                    branding.editorUpdate {
                        $0[keyPath: path] = next
                        $0.hasCustomAppearance = true
                    }
                }), default: defaults[keyPath: path])
    }

    func slider(
        _ title: LocalizedStringKey, _ path: WritableKeyPath<SpaceCrest, Double>,
        range: ClosedRange<Double> = 0...1, readout: CrestSettingSliderReadout = .percent
    ) -> some View {
        BrowserCrestStudioSlider(title: title, value: crest(path), range: range, readout: readout)
    }

    func count(_ title: LocalizedStringKey, _ path: WritableKeyPath<SpaceCrest, Int>, range: ClosedRange<Int>)
        -> some View
    {
        let value = crest(path)
        return CrestSettingRow(title, setting: value.resettable(title)) {
            Stepper(value: value.binding, in: range) { Text(value.wrappedValue.formatted()).monospacedDigit() }
                .fixedSize()
        }
    }

    func picker<Option: Hashable & BrowserSpaceHeraldicTerm>(
        _ title: LocalizedStringKey, _ path: WritableKeyPath<SpaceCrest, Option>, options: [Option]
    ) -> some View {
        let value = crest(path)
        return CrestSettingRow(title, setting: value.resettable(title)) {
            Picker(title, selection: value.binding) {
                ForEach(options, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            #if os(macOS)
                .fixedSize()
            #endif
        }
    }
}

struct BrowserCrestStudioSlider: View {
    @Environment(\.crestStudioEditingChanged) private var editingChanged
    let title: LocalizedStringKey
    let value: CrestSettingValue<Double>
    var range: ClosedRange<Double> = 0...1
    var readout: CrestSettingSliderReadout = .percent

    var body: some View {
        CrestSettingSlider(
            title, value: value, range: range, readout: readout,
            onEditingChanged: editingChanged.callAsFunction
        )
    }
}

extension EnvironmentValues {
    @Entry var crestStudioEditingChanged = BrowserCrestStudioEditingAction()
}

struct BrowserCrestStudioEditingAction {
    var update: (Bool) -> Void = { _ in }

    func callAsFunction(_ editing: Bool) { update(editing) }
}

struct BrowserCrestStudioChoice<Artwork: View>: View {
    let title: LocalizedStringResource
    let selected: Bool
    let select: () -> Void
    @ViewBuilder var artwork: Artwork

    var body: some View {
        CrestSelectableCard(isSelected: selected, accessibilityLabel: Text(title), density: .compact, action: select) {
            VStack(spacing: 4) {
                artwork.frame(width: 64, height: 58)
                // Every tile keeps room for two lines, so a long name wraps
                // where the tile is narrow and the tiles in a row stay even.
                Text(title).font(.caption).lineLimit(2, reservesSpace: true).multilineTextAlignment(.center)
                    .frame(minHeight: 30, alignment: .top)
            }
        }
    }
}
