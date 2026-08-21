import SwiftUI

/// Find in page, on every shell.
///
/// Everything the bar needs from the page arrives through `BrowserFindPort`,
/// everything about how big it is comes from `BrowserFindBarMetrics`, and the
/// two things a shell genuinely dresses differently — the surface under the bar
/// and what the query field does to typed text — arrive through its own
/// `BrowserPlatform*` pair. So the two shells share this bar rather than a
/// resemblance.
///
/// Focus is not one of those things. Both shells ask for the query field
/// outright, keyed on the page's focus request, because both have the same
/// problem: a bar that is already on screen when find is asked for again has
/// nothing else to notice. macOS declared a default focus for the scope
/// instead, which the window only evaluates as the scope appears — so the
/// second `⌘F` left the field alone, and after the move it stopped landing on
/// the first one too.
struct BrowserFindBar: View {
    let port: BrowserFindPort
    let capabilities: BrowserInteractionCapabilities

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var query = ""
    @FocusState private var focusedField: BrowserFindBarField?

    var body: some View {
        HStack(spacing: metrics.itemSpacing) {
            queryField

            BrowserFindMatchStatus(state: port.matchState(), metrics: metrics)

            control(
                "Previous Match",
                systemImage: "chevron.up",
                isEnabled: !query.isEmpty
            ) {
                port.find(query, .backward)
            }

            control(
                "Next Match",
                systemImage: "chevron.down",
                isEnabled: !query.isEmpty
            ) {
                port.find(query, .forward)
            }

            control("Close Find", systemImage: "xmark", action: port.dismiss)
        }
        .labelStyle(.iconOnly)
        .padding(.leading, metrics.leadingPadding)
        .padding(.trailing, metrics.trailingPadding)
        .modifier(
            BrowserFindBarBand(
                height: metrics.barHeight,
                growsWithContent: metrics.growsWithContent
            )
        )
        .modifier(BrowserPlatformFindBarStyle())
        .shadow(
            color: .black.opacity(
                reduceTransparency ? 0 : BrowserFindBarMetrics.shadowOpacity
            ),
            radius: BrowserFindBarMetrics.shadowRadius,
            y: BrowserFindBarMetrics.shadowOffset
        )
        .task(id: port.focusRequest()) {
            focusedField = .query
        }
        .onChange(of: query) {
            port.find(query, .forward)
        }
        .onKeyPress(.escape) {
            port.dismiss()
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("find-bar")
    }

    private var queryField: some View {
        TextField("Find in Page", text: $query)
            .textFieldStyle(.plain)
            .modifier(BrowserPlatformFindQueryInputModifier())
            .focused($focusedField, equals: .query)
            .frame(width: metrics.queryWidth)
            .onSubmit {
                port.find(query, .forward)
            }
            .accessibilityIdentifier("find-field")
    }

    /// One of the bar's three glyph controls, claiming a hit target only where
    /// the shell's profile asks for one.
    @ViewBuilder
    private func control(
        _ title: String,
        systemImage: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(title, systemImage: systemImage, action: action)
            .disabled(!isEnabled)

        if let controlSize = metrics.controlSize {
            button
                .frame(width: controlSize.width, height: controlSize.height)
                .contentShape(.rect)
        } else {
            button
        }
    }

    private var metrics: BrowserFindBarMetrics {
        BrowserFindBarMetrics.resolve(capabilities)
    }
}
