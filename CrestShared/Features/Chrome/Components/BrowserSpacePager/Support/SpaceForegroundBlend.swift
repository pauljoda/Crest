import SwiftUI

extension EnvironmentValues {
    @Entry var spaceChromeAccent: Color? = nil
    @Entry var spaceChromeForeground: Color? = nil
    @Entry var spacePagerProgress: SpacePagerProgress? = nil
}

/// Where the Space pager stands among the Spaces, in the order its position
/// runs along, for chrome that blends from one Space to the next with it.
struct SpacePagerProgress: Equatable, Sendable {
    let position: CGFloat
    let order: [UUID]
}

/// Fixed chrome follows visible Space progress without observing it in tab rows.
struct SpaceForegroundBlend: ViewModifier {
    // MARK: - Variables

    let ids: [UUID]
    let brandings: [SpaceBranding]
    let accents: [Color]
    let selectedSpaceID: UUID?

    @Environment(\.spacePagerPresentation) private var presentation
    @Environment(\.colorScheme) private var colorScheme
    @State private var foreground = SpaceForegroundPresentation()

    /// Each Space's text tone over the window's appearance.
    private var tones: [SpaceForegroundPresentation.Tone] {
        zip(ids, brandings).map { id, branding in
            SpaceForegroundPresentation.Tone(
                id: id, white: branding.shown.foregroundTone(over: colorScheme) == .light ? 1 : 0)
        }
    }

    /// Each Space's index in the order the pager's position runs along.
    private var arrangement: [Int] {
        guard let order = foreground.order else { return Array(ids.indices) }
        let indices = order.compactMap { ids.firstIndex(of: $0) }
        return indices.count == ids.count ? indices : Array(ids.indices)
    }

    // MARK: - Initializers

    init(spaces: [SpaceModel], selectedSpaceID: UUID?) {
        ids = spaces.map(\.id)
        brandings = spaces.map(\.settings.look)
        accents = brandings.map { $0.primaryColor.color }
        self.selectedSpaceID = selectedSpaceID
    }

    // MARK: - Actions - Presentation

    func body(content: Content) -> some View {
        let tones = tones
        let arrangement = arrangement
        content
            .modifier(
                SpaceForegroundTone(
                    position: foreground.position ?? CGFloat(tones.firstIndex { $0.id == selectedSpaceID } ?? 0),
                    tones: arrangement.map { tones[$0] }, accents: arrangement.map { accents[$0] },
                    order: arrangement.map { ids[$0] })
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
    let order: [UUID]

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
            .environment(\.spacePagerProgress, SpacePagerProgress(position: position, order: order))
    }

    private var accent: Color? {
        guard let sample = SpacePagerInterpolation(position: position, count: accents.count) else { return nil }
        return accents[sample.lower].mix(with: accents[sample.upper], by: Double(sample.fraction), in: .device)
    }
}
