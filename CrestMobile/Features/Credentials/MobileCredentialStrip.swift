import SwiftUI

// MARK: - Types

/// What the strip does to its page, as closures that hold the page weakly.
struct MobileCredentialStripActions {
    /// Fills a saved login into the form of the request it was offered for.
    let fill: (CredentialDescriptor, UUID) -> Void

    /// Opens the full offer for the request in a band at the top of the page.
    let showOffer: (UUID) -> Void

    /// Moves focus to the previous field, -1, or the next one, 1.
    let focusAdjacentField: (Int) -> Void

    /// Ends editing and puts the keyboard away.
    let done: () -> Void
}

/// The strip a phone shows above the keyboard in place of WebKit's own bar:
/// the site's saved logins as chips when a sign-in field is focused, or the
/// offer of a strong password for a new one, then the previous and next field
/// buttons and Done. Choosing a login fills it; More opens the full offer in a
/// band at the top of the page.
struct MobileCredentialStrip: View {
    // MARK: - Static Variables

    /// The strip's height above the keyboard.
    static let height: CGFloat = 48

    /// How many logins the strip shows before More.
    private static let shownLogins = 3

    // MARK: - Variables

    let state: BrowserCredentialPageState<BrowserCredentialSession.FillTarget>
    let browser: BrowserStore
    let actions: MobileCredentialStripActions

    @State private var model = BrowserCredentialSuggestionModel()

    var body: some View {
        HStack(spacing: CrestSpacing.extraSmall) {
            ScrollView(.horizontal) {
                HStack(spacing: CrestSpacing.extraSmall) {
                    chips
                }
                .padding(.horizontal, CrestSpacing.extraSmall)
            }
            .scrollIndicators(.hidden)
            Group {
                Button {
                    actions.focusAdjacentField(-1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .accessibilityLabel("Previous Field")
                Button {
                    actions.focusAdjacentField(1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .accessibilityLabel("Next Field")
            }
            .buttonStyle(CrestChromeButtonStyle(controlSize: CGSize(width: 40, height: 40)))
            Button("Done", action: actions.done)
                .fontWeight(.semibold)
                .buttonStyle(CrestChromeButtonStyle(controlSize: nil))
        }
        .foregroundStyle(CrestBrandTheme.accentText)
        .padding(.trailing, CrestSpacing.small)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(CrestBrandTheme.flyout)
        .overlay(alignment: .top) { Divider() }
        .task(id: request?.id) {
            guard let request, request.passwordKind == .current else {
                model.cancel()
                return
            }
            await model.load(request, in: state.spaceID, using: browser)
        }
    }

    private var request: BrowserCredentialFillRequest? {
        state.fillRequest
    }

    @ViewBuilder
    private var chips: some View {
        if let request {
            if request.passwordKind == .new {
                chip(Text("Use Strong Password"), systemImage: "key.horizontal.fill", isFirst: true, fitsTitle: true) {
                    actions.showOffer(request.id)
                }
            } else {
                ForEach(Array(model.suggestions.prefix(Self.shownLogins).enumerated()), id: \.element.id) {
                    index, login in
                    chip(Text(verbatim: login.username), systemImage: "person.fill", isFirst: index == 0) {
                        actions.fill(login, request.id)
                    }
                }
                if model.suggestions.count > Self.shownLogins {
                    chip(Text("More"), systemImage: "ellipsis", isFirst: false) {
                        actions.showOffer(request.id)
                    }
                }
            }
        }
    }

    /// A chip of the strip. A login's chip gives up the middle of a long
    /// username; an offer's keeps its whole title.
    private func chip(
        _ title: Text, systemImage: String, isFirst: Bool, fitsTitle: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                title
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: systemImage)
            }
            .font(.subheadline.weight(isFirst ? .semibold : .regular))
            .padding(.horizontal, CrestSpacing.small)
            .fixedSize(horizontal: fitsTitle, vertical: false)
            .frame(maxWidth: fitsTitle ? nil : 190, minHeight: 34)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isFirst ? CrestBrandTheme.accentText : .primary)
        .crestHoverSurface(isSelected: isFirst, cornerRadius: CrestRadius.compact, showsRestingSurface: true)
    }
}
