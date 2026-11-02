import SwiftUI

/// Hosts a window's controls in the system toolbar where iOS lays bars out down
/// the side of the window: iPhone Duo, built with the iOS 27.1 SDK.
///
/// The content sits in a navigation stack whose bars carry the items the chrome
/// contributes through `.toolbar`. The system places them in the side column,
/// clear of the status bar and the camera. Held upright, the display keeps a
/// band across its top for the status bar and a top bar, and the items take
/// the top bar. Anywhere else the bars stay hidden, and the chrome draws its
/// own controls as it always has.
struct MobileBrowserSideToolbarHost: ViewModifier {
    /// The browser whose shown Space's tone the bar's glass follows. It is
    /// read here rather than by the view that applies this, so a change to the
    /// window never rebuilds that view in the middle of a change it is making.
    var browser: BrowserStore?
    /// The scheme the bar's glass follows where no browser is given, or nil
    /// for the system's.
    var colorScheme: ColorScheme?

    @Environment(\.mobileBrowserSideToolbarIsHosted) private var isHosted
    @Environment(\.colorScheme) private var contentColorScheme

    func body(content: Content) -> some View {
        if isHosted {
            // A stack already carries this window's bars; a second one would
            // take the items meant for it.
            content
        } else {
            #if canImport(SwiftUICore, _version: 8.0.85)
                if #available(iOS 27.1, *) {
                    MobileBrowserSideToolbarStack(
                        colorScheme: barColorScheme ?? contentColorScheme,
                        contentColorScheme: contentColorScheme
                    ) {
                        content
                    }
                } else {
                    content
                }
            #else
                content
            #endif
        }
    }

    private var barColorScheme: ColorScheme? {
        browser?.shownSpace?.settings.look.colorScheme(over: contentColorScheme) ?? colorScheme
    }
}

#if canImport(SwiftUICore, _version: 8.0.85)
    /// The navigation stack whose bars carry the side toolbar, once the system
    /// has asked for one or the display keeps a top band for a top bar. A
    /// device that does neither keeps its content exactly as it was; one that
    /// has kept the stack from then on, so turning or folding it never rebuilds
    /// the window's content.
    @available(iOS 27.1, *)
    private struct MobileBrowserSideToolbarStack<Content: View>: View {
        let colorScheme: ColorScheme
        let contentColorScheme: ColorScheme
        @ViewBuilder let content: Content

        @Environment(\.toolbarVerticalEdge) private var verticalEdge
        @State private var hostsBars = false
        @State private var folds = false
        @State private var isUpright = false

        var body: some View {
            Group {
                if hostsBars || verticalEdge != nil || sharesTopBandWithStatusBar {
                    // The bars draw in the stack's scheme and the content gets
                    // its own back, so only the bar's glass takes the tone.
                    NavigationStack {
                        MobileBrowserSideToolbarContent(sharesTopBandWithStatusBar: sharesTopBandWithStatusBar) {
                            content
                                .environment(\.colorScheme, contentColorScheme)
                        }
                    }
                    .environment(\.colorScheme, colorScheme)
                } else {
                    content
                }
            }
            .background { MobileBrowserHingeObserver(folds: $folds) }
            .background { uprightProbe }
            .onChange(of: verticalEdge != nil || sharesTopBandWithStatusBar, initial: true) { _, asksForBars in
                if asksForBars { hostsBars = true }
            }
        }

        /// Reads whether the window stands upright from its whole height: the
        /// keyboard shortens the layout but never turns the display on its side.
        private var uprightProbe: some View {
            Color.clear
                .onGeometryChange(for: Bool.self) {
                    $0.size.height > $0.size.width
                } action: {
                    isUpright = $0
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .accessibilityHidden(true)
        }

        /// A foldable's inner display held upright keeps a band across its top
        /// for the status bar and a top bar. Its outer display and the inner
        /// one turned on its side lay bars down the side instead, which the
        /// vertical edge says first.
        private var sharesTopBandWithStatusBar: Bool {
            folds && isUpright
        }
    }

    /// Learns whether the device folds, as iPhone Duo does, from the hinge the
    /// system reports. A device folds for good once it has reported one: the
    /// system also reports no hinge as the window's content is rebuilt.
    @available(iOS 27.1, *)
    private struct MobileBrowserHingeObserver: UIViewRepresentable {
        @Binding var folds: Bool

        func makeUIView(context: Context) -> UIView {
            let view = UIView()
            view.isUserInteractionEnabled = false
            view.addInteraction(
                UIHingeInteraction { [folds = $folds] _, update in
                    if update.hinge != nil { folds.wrappedValue = true }
                })
            return view
        }

        func updateUIView(_ uiView: UIView, context: Context) {}
    }

    /// The stack's root: it learns from the system which edge the bars prefer
    /// and tells the chrome below whether its controls are toolbar items.
    @available(iOS 27.1, *)
    private struct MobileBrowserSideToolbarContent<Content: View>: View {
        let sharesTopBandWithStatusBar: Bool
        @ViewBuilder let content: Content

        @Environment(\.toolbarVerticalEdge) private var verticalEdge

        var body: some View {
            let placement = MobileBrowserControlPlacement.fitting(
                verticalEdge: verticalEdge, sharesTopBandWithStatusBar: sharesTopBandWithStatusBar)
            content
                .environment(\.mobileBrowserControlPlacement, placement)
                .environment(\.mobileBrowserSideToolbarIsHosted, true)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarVisibility(placement.barVisibility, for: .navigationBar, .bottomBar)
                // Items in the side column still give the navigation bar a
                // top inset of its own; the display's top is already clear.
                .ignoresSafeArea(.container, edges: placement.runsDownSide ? .top : [])
        }
    }
#endif

extension EnvironmentValues {
    /// Whether a side toolbar host already wraps this view. A presentation
    /// starts a window's controls over, so it sets this back to false.
    @Entry var mobileBrowserSideToolbarIsHosted = false
}
