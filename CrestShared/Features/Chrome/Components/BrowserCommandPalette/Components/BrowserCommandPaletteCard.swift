import SwiftUI

/// The palette's query field and results on the palette's surface.
///
/// An overlay card given a namespace and a resting width grows out of its
/// Space's sidebar address field and shrinks back into it. Its surface takes
/// the field's frame and corner radius and animates to its own, while the
/// contents keep their resting layout and show through the growing frame from
/// the top, so no text is squeezed on the way. The field hands over the shared
/// identity as the card arrives (``BrowserCommandPaletteHandoff``); where no
/// field holds it, the card simply appears where it rests.
struct BrowserCommandPaletteCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.browserCommandPaletteTransitionPhase) private var transitionPhase

    let model: BrowserCommandPaletteModel
    let presentation: BrowserCommandPalettePresentation
    let maximumResultAreaHeight: CGFloat
    let morphNamespace: Namespace.ID?
    /// The width the card comes to rest at, which its contents keep while the
    /// card's frame morphs. Absent where the card never morphs.
    let restingWidth: CGFloat?
    let queryIsFocused: FocusState<Bool>.Binding

    /// How much taller than its minimum the input line has grown at a larger
    /// text size.
    @State private var fieldExcessHeight: CGFloat = 0
    /// How tall the provider chips' row is, which a larger text size makes
    /// taller than its least height.
    @State private var chipRowHeight = BrowserCommandPaletteMetrics.providerChipRowHeight

    /// Whether the card has arrived, rather than growing in or shrinking away.
    private var isSettled: Bool { transitionPhase.isIdentity }

    var body: some View {
        surface
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("command-palette")
    }

    @ViewBuilder
    private var surface: some View {
        let animates =
            morphNamespace != nil && restingWidth != nil
            && BrowserCommandSurfaceMorph.animatesCommandPalette(reduceMotion: reduceMotion)
        let travelOffset: CGFloat =
            if !animates || isSettled {
                0
            } else if presentation.listsUpward {
                12
            } else {
                -12
            }
        contents
            .frame(maxWidth: restingWidth ?? BrowserCommandPaletteMetrics.maximumCardWidth)
            .modifier(BrowserCommandPaletteShellMaterial(shape: restingShape))
            .clipShape(restingShape)
            .modifier(BrowserCommandPaletteCardEdge(cornerRadius: presentation.cornerRadius))
            .modifier(BrowserSearchProviderGlow(color: model.activeProvider?.color, shape: restingShape))
            .offset(y: travelOffset)
            .opacity(isSettled ? 1 : 0)
    }

    /// The field, the provider chips while what is typed names some, and the
    /// results, which a palette rising from the bottom of the screen lists
    /// above the field. An overlay card keeps one height whatever the results,
    /// so it never moves as they change; the chips take their room from the
    /// results.
    private var contents: some View {
        VStack(spacing: 0) {
            if presentation.listsUpward {
                if showsResults {
                    results
                    Divider()
                }
                chips
                field
            } else {
                field
                chips
                if showsResults {
                    Divider()
                    results
                }
            }
        }
        .browserCommandPalettePointerTracking(model: model)
    }

    private var field: some View {
        BrowserCommandPaletteSearchField(
            model: model,
            presentation: presentation,
            queryIsFocused: queryIsFocused
        )
        .onGeometryChange(for: CGFloat.self) {
            $0.size.height
        } action: {
            fieldExcessHeight = max(0, $0 - presentation.input.minimumHeight)
        }
        // Over the results. A card resting under the window's title bar
        // stretches the results' scroll view up into the title bar's safe
        // area, over the field, where it would take the field's presses.
        .zIndex(1)
    }

    @ViewBuilder
    private var chips: some View {
        if !model.providerChips.isEmpty {
            BrowserCommandPaletteProviderChips(model: model)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    chipRowHeight = $0
                }
        }
    }

    private var results: some View {
        BrowserCommandPaletteResultList(
            model: model,
            maximumResultAreaHeight: resultAreaHeight,
            fillsHeight: keepsHeight,
            listsUpward: presentation.listsUpward
        )
    }

    private var showsResults: Bool { keepsHeight || !model.groups.isEmpty }

    /// Whether the card keeps one height while its results change.
    private var keepsHeight: Bool { presentation.keepsHeight }

    /// The height the results may take, less what the provider chips take
    /// from a card that keeps its height or fills what its field leaves it,
    /// and less what a larger text size adds to that field's input line.
    private var resultAreaHeight: CGFloat {
        guard keepsHeight || presentation.growsFromField else { return maximumResultAreaHeight }
        let chips = model.providerChips.isEmpty ? 0 : chipRowHeight
        let grownField = presentation.growsFromField ? fieldExcessHeight : 0
        return max(0, maximumResultAreaHeight - chips - grownField)
    }

    private var restingShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: presentation.cornerRadius, style: .continuous)
    }
}
