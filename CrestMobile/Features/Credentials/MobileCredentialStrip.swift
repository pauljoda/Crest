import SwiftUI

// MARK: - Types

/// What the strip does to its page, as closures that hold the page weakly.
struct MobileCredentialStripActions {
    /// Fills a saved login into the form of the request it was offered for.
    let fill: (CredentialDescriptor, UUID) -> Void

    /// Fills the values the core planned, such as a one-time code, into the
    /// form of the request they were offered for.
    let fillValues: ([BrowserAutofillValue], UUID) -> Void

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
    @State private var codes: [BrowserCodeSuggestion] = []
    @State private var records: [BrowserAutofillSuggestion] = []

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
            codes = []
            records = []
            if let request, let offer = request.autofill {
                model.cancel()
                await loadRecords(for: offer)
                return
            }
            if let request, request.codeFields != nil {
                model.cancel()
                await loadCodes(for: request)
                return
            }
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
            if request.autofill != nil {
                ForEach(Array(records.prefix(Self.shownLogins).enumerated()), id: \.element.id) { index, record in
                    chip(Text(verbatim: record.title), systemImage: record.systemImage, isFirst: index == 0) {
                        actions.showOffer(request.id)
                    }
                }
            } else if let fields = request.codeFields {
                ForEach(Array(codes.prefix(Self.shownLogins).enumerated()), id: \.element.id) { index, suggestion in
                    chip(
                        Text("Code for \(suggestion.descriptor.username)"), systemImage: "clock.badge.checkmark",
                        isFirst: index == 0
                    ) {
                        guard let code = browser.oneTimeCode(forLink: suggestion.link, at: .now),
                            let values = browser.spread(code.code, into: fields)
                        else { return }
                        actions.fillValues(values, request.id)
                    }
                }
            } else if request.passwordKind == .new {
                chip(Text("Use Strong Password"), systemImage: "key.horizontal.fill", isFirst: true, fitsTitle: true) {
                    actions.showOffer(request.id)
                }
            } else if model.hasFailed {
                // The saved logins couldn't be read: the strip says so and
                // reads them again on a tap.
                chip(Text("Try Again"), systemImage: "arrow.clockwise", isFirst: true, fitsTitle: true) {
                    Task { await model.load(request, in: state.spaceID, using: browser) }
                }
                .accessibilityHint(Text("Crest couldn’t read the saved passwords."))
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

    /// The person's addresses or cards, as the strip names them; a chip opens
    /// the full offer, which fills and, for a card, authenticates.
    private func loadRecords(for offer: BrowserAutofillOffer) async {
        var found: [BrowserAutofillSuggestion] = []
        if offer.takesCard {
            for card in (try? await browser.savedCards()) ?? [] {
                found.append(
                    BrowserAutofillSuggestion(
                        id: card.id, title: card.title, detail: "", systemImage: "creditcard.fill"))
            }
        } else {
            for address in (try? await browser.savedAddresses()) ?? [] {
                found.append(
                    BrowserAutofillSuggestion(
                        id: address.id, title: address.label.nilIfEmpty ?? address.oneLine, detail: "",
                        systemImage: "house.fill"))
            }
        }
        guard !Task.isCancelled else { return }
        records = found
    }

    /// The site's logins that make codes, the one the page just filled first.
    private func loadCodes(for request: BrowserCredentialFillRequest) async {
        let logins = (try? await browser.credentialSuggestions(for: request.origin, in: state.spaceID)) ?? []
        var found: [BrowserCodeSuggestion] = []
        for login in logins {
            if let link = try? await browser.credentialExtras(id: login.id, in: state.spaceID)?.codeLink {
                found.append(BrowserCodeSuggestion(descriptor: login, link: link))
            }
        }
        if let last = state.lastFilledCredentialID, let index = found.firstIndex(where: { $0.id == last }) {
            found.insert(found.remove(at: index), at: 0)
        }
        guard !Task.isCancelled else { return }
        codes = found
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
