import SwiftUI

extension EnvironmentValues {
    @Entry var spaceChromeAccent: Color? = nil
    @Entry var spaceChromeForeground: Color? = nil
}

/// Fixed chrome follows visible Space progress without observing it in tab rows.
struct SpaceForegroundBlend: ViewModifier {
    let tones: [SpaceForegroundPresentation.Tone]
    let accents: [Color]
    let selectedSpaceID: SpaceID?

    @Environment(\.spacePagerPresentation) private var presentation
    @State private var foreground = SpaceForegroundPresentation()

    init(spaces: [BrowserSpace], selectedSpaceID: SpaceID?) {
        tones = spaces.map {
            SpaceForegroundPresentation.Tone(
                id: $0.id,
                white: BrowserSpaceForegroundPolicy.tone(for: $0.branding) == .light ? 1 : 0)
        }
        accents = spaces.map { $0.branding.primaryColor.color }
        self.selectedSpaceID = selectedSpaceID
    }

    func body(content: Content) -> some View {
        content
            .modifier(
                SpaceForegroundTone(
                    position: foreground.position ?? CGFloat(tones.firstIndex { $0.id == selectedSpaceID } ?? 0),
                    tones: tones, accents: accents)
            )
            .onAppear { foreground.connect(presentation, tones: tones, selectedSpaceID: selectedSpaceID) }
            .onChange(of: tones) { _, _ in
                foreground.connect(presentation, tones: tones, selectedSpaceID: selectedSpaceID)
            }
            .onChange(of: selectedSpaceID) { _, _ in
                foreground.connect(presentation, tones: tones, selectedSpaceID: selectedSpaceID)
            }
            .onChange(of: presentation.map(ObjectIdentifier.init)) { _, _ in
                foreground.connect(presentation, tones: tones, selectedSpaceID: selectedSpaceID)
            }
            .onDisappear { foreground.disconnect() }
    }
}

private struct SpaceForegroundTone: ViewModifier, Animatable {
    nonisolated var position: CGFloat
    let tones: [SpaceForegroundPresentation.Tone]
    let accents: [Color]

    nonisolated var animatableData: CGFloat {
        get { position }
        set { position = newValue }
    }

    func body(content: Content) -> some View {
        let foreground = Color(white: SpaceForegroundPresentation.white(at: position, tones: tones))
        content
            .foregroundStyle(foreground)
            .environment(\.spaceChromeForeground, foreground)
            .environment(\.spaceChromeAccent, accent)
    }

    private var accent: Color? {
        guard let sample = SpacePagerInterpolation(position: position, count: accents.count) else { return nil }
        return accents[sample.lower].mix(with: accents[sample.upper], by: Double(sample.fraction), in: .device)
    }
}
