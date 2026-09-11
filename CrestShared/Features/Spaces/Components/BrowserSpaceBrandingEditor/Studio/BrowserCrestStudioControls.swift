import SwiftUI

/// Bindings normalize at the editing boundary, shared by setup drafts and live Spaces.
@MainActor
struct BrowserCrestStudioContext {
    let branding: Binding<BrowserSpaceBranding>
    let defaults: BrowserSpaceBranding
    var compact: Bool
    var previewBranding: BrowserSpaceBranding?
    var value: BrowserSpaceBranding { branding.wrappedValue }

    func preview(_ mutation: (inout BrowserSpaceBranding) -> Void) -> BrowserSpaceBranding {
        var candidate = previewBranding ?? value
        candidate.iconStyle = .layeredCrest
        mutation(&candidate)
        return candidate.normalized()
    }

    func crest<Value: Equatable>(_ path: WritableKeyPath<BrowserSpaceCrest, Value>) -> CrestSettingValue<Value> {
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

    func setting<Value: Equatable>(_ path: WritableKeyPath<BrowserSpaceBranding, Value>) -> CrestSettingValue<Value> {
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
        _ title: LocalizedStringKey, _ path: WritableKeyPath<BrowserSpaceCrest, Double>,
        range: ClosedRange<Double> = 0...1, readout: CrestSettingSliderReadout = .percent
    ) -> some View {
        BrowserCrestStudioSlider(title: title, value: crest(path), range: range, readout: readout)
    }

    func count(_ title: LocalizedStringKey, _ path: WritableKeyPath<BrowserSpaceCrest, Int>, range: ClosedRange<Int>)
        -> some View
    {
        let value = crest(path)
        return CrestSettingRow(title, setting: value.resettable(title)) {
            Stepper(value: value.binding, in: range) { Text(value.wrappedValue.formatted()).monospacedDigit() }
                .fixedSize()
        }
    }

    func picker<Option: Hashable & BrowserSpaceHeraldicTerm>(
        _ title: LocalizedStringKey, _ path: WritableKeyPath<BrowserSpaceCrest, Option>, options: [Option]
    ) -> some View {
        let value = crest(path)
        return CrestSettingRow(title, setting: value.resettable(title)) {
            Picker(title, selection: value.binding) {
                ForEach(options, id: \.self) { Text($0.titleKey).tag($0) }
            }.labelsHidden().fixedSize()
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
        VStack(spacing: 8) {
            CrestSettingRow(title, setting: value.resettable(title)) {
                Text(readout.label(value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value.binding, in: range, onEditingChanged: editingChanged.callAsFunction) { Text(title) }
                .labelsHidden()
                .accessibilityLabel(Text(title))
                .accessibilityValue(readout.label(value.wrappedValue))
        }
    }
}

/// Small cards keep one scroll owner in Settings and in onboarding.
struct BrowserCrestStudioGroup<Content: View>: View {
    let title: LocalizedStringKey
    var preview: BrowserSpaceBranding? = nil
    var symbol: String = "sparkles"
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if let preview {
                    BrowserCrestStudioMark(branding: preview, symbol: symbol, size: 56)
                        .frame(width: 72, height: 64)
                        .background { BrowserSpaceBannerBackground(branding: preview) }
                        .clipShape(.rect(cornerRadius: 12))
                        .accessibilityHidden(true)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.035), in: .rect(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.055)) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }
}

/// Each choice renders the current composition with just this property changed.
struct BrowserCrestStudioGallery<Option: Hashable & BrowserSpaceHeraldicTerm>: View {
    let context: BrowserCrestStudioContext
    let title: LocalizedStringKey
    let path: WritableKeyPath<BrowserSpaceCrest, Option>
    let options: [Option]

    var body: some View {
        let value = context.crest(path)
        VStack(alignment: .leading, spacing: 10) {
            CrestSettingRow(title, setting: value.resettable(title)) {
                Text(value.wrappedValue.titleKey).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
                ForEach(options, id: \.self) { option in
                    BrowserCrestStudioChoice(title: option.titleKey, selected: option == value.wrappedValue) {
                        value.binding.wrappedValue = option
                    } artwork: {
                        BrowserSpaceCrestIcon(
                            branding: context.preview {
                                $0.crest[keyPath: path] = option
                            }, size: 52, rasterizesLayers: false
                        )
                        .equatable()
                    }
                }
            }
        }
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
    let title: LocalizedStringKey
    let selected: Bool
    let select: () -> Void
    @ViewBuilder var artwork: Artwork

    var body: some View {
        Button(action: select) {
            VStack(spacing: 4) {
                artwork.frame(width: 64, height: 58)
                Text(title).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                    .frame(height: 30, alignment: .top)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                selected ? CrestBrandTheme.accent.opacity(0.12) : .primary.opacity(0.035), in: .rect(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12).strokeBorder(
                    selected ? CrestBrandTheme.accent : .clear, lineWidth: 2)
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
