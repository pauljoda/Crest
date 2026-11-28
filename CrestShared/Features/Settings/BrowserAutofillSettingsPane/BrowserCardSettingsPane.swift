import SwiftUI

/// Settings › Autofill › Payment Cards: the person's cards as tiles with
/// their nickname, network and last four, shared by every Space, searchable by
/// those. Opening one asks for Touch ID or the device password, since its
/// editor shows the number.
struct BrowserCardSettingsPane<Header: View>: View {
    let browser: BrowserStore
    @ViewBuilder let header: Header

    @State private var cards: [BrowserSavedCard] = []
    @State private var addresses: [AddressRecord] = []
    @State private var editing: CardRecord?
    @State private var errorMessage: String?
    @State private var searchText = ""

    var body: some View {
        BrowserSettingsPane(.passwords) {
            BrowserSettingsPaneNote { header }
            BrowserSettingsSectionSlot(.paymentCards) {
                Section("Payment cards") {
                    if !cards.isEmpty {
                        CrestSearchField("Search payment cards", text: $searchText)
                            .accessibilityIdentifier("card-search")
                    }
                    if !searchText.isEmpty, shownCards.isEmpty {
                        Text("No matches").foregroundStyle(.secondary)
                    }
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 180), spacing: CrestSpacing.medium)],
                        spacing: CrestSpacing.medium
                    ) {
                        ForEach(Array(shownCards.enumerated()), id: \.element.id) { index, card in
                            Button {
                                Task { await open(card) }
                            } label: {
                                BrowserCardTile(card: card, tint: Self.tint(index))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("card-tile-\(card.id)")
                        }
                    }
                    .padding(.vertical, CrestSpacing.extraSmall)
                    Button("Add Card", systemImage: "plus") {
                        editing = CardRecord(
                            id: UUID(), nickname: "", cardholder: "", number: "", expiryMonth: 1,
                            expiryYear: Calendar.current.component(.year, from: .now) + 2, securityCode: nil,
                            billingAddressID: nil)
                    }
                    .accessibilityIdentifier("add-card")
                }
            }
            BrowserSettingsPaneNote {
                if let errorMessage {
                    BrowserCredentialErrorSection(message: errorMessage)
                }
            }
        }
        .task { await load() }
        .sheet(item: $editing) { card in
            BrowserCardEditor(
                browser: browser, card: card, isNew: !cards.contains { $0.id == card.id }, addresses: addresses
            ) { result in
                editing = nil
                Task { await apply(result) }
            }
        }
    }

    /// The cards whose nickname, network, last four or expiry holds every
    /// word searched for.
    private var shownCards: [BrowserSavedCard] {
        let words = searchText.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return cards }
        return cards.filter { card in
            let text = [
                card.title, card.nickname, String(localized: card.network.displayName), card.lastFour, card.expiry,
            ]
            .joined(separator: " ")
            return words.allSatisfy { text.localizedStandardContains($0) }
        }
    }

    /// The template house colours the tiles take in turn.
    private static func tint(_ index: Int) -> Color {
        let palette = [
            CrestBrandPalette.sky, CrestBrandPalette.coral, CrestBrandPalette.sage, CrestBrandPalette.butter,
        ]
        return palette[index % palette.count]
    }

    private func load() async {
        do {
            cards = try await browser.savedCards()
            addresses = try await browser.savedAddresses()
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Crest couldn’t read your payment cards.")
        }
    }

    private func open(_ card: BrowserSavedCard) async {
        do {
            guard
                try await BrowserCredentialSensitiveAccess(browser: browser).authenticate(
                    reason: String(localized: "Authenticate to show \(card.title)."))
            else { return }
            editing = try await browser.card(id: card.id)
        } catch {
            errorMessage = String(localized: "Crest couldn’t read that card.")
        }
    }

    private func apply(_ result: BrowserAutofillEditResult<CardRecord>) async {
        do {
            switch result {
            case .save(let card): try await browser.saveCard(card)
            case .delete(let id): try await browser.deleteCard(id: id)
            case .cancel: return
            }
            await load()
        } catch {
            errorMessage = String(localized: "Crest couldn’t save that card.")
        }
    }
}

/// A saved card as a tile: its name, last four, expiry and network.
struct BrowserCardTile: View {
    let card: BrowserSavedCard
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.small) {
            Text(verbatim: card.title)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(verbatim: "•••• \(card.lastFour)")
                .font(.body.monospaced())
            HStack {
                Text(verbatim: card.expiry)
                Spacer()
                Text(card.network.displayName).fontWeight(.bold)
            }
            .font(.caption)
        }
        .foregroundStyle(.white)
        .padding(CrestSpacing.medium)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(
            LinearGradient(
                colors: [tint.mix(with: .black, by: 0.45), tint], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: CrestRadius.compact * 1.5)
        )
        .crestHoverSurface(cornerRadius: CrestRadius.compact * 1.5)
    }
}

/// One card: its nickname, cardholder, number, expiry, an optional security
/// code and billing address, and Delete for a saved one.
struct BrowserCardEditor: View {
    let browser: BrowserStore
    @State var card: CardRecord
    let isNew: Bool
    let addresses: [AddressRecord]
    let finish: (BrowserAutofillEditResult<CardRecord>) -> Void

    @State private var confirmsDeletion = false
    @State private var keepsSecurityCode: Bool

    init(
        browser: BrowserStore, card: CardRecord, isNew: Bool, addresses: [AddressRecord],
        finish: @escaping (BrowserAutofillEditResult<CardRecord>) -> Void
    ) {
        self.browser = browser
        _card = State(initialValue: card)
        self.isNew = isNew
        self.addresses = addresses
        self.finish = finish
        _keepsSecurityCode = State(initialValue: card.securityCode != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nickname", text: $card.nickname, prompt: Text("Everyday"))
                    TextField("Name on card", text: $card.cardholder)
                    TextField("Card number", text: $card.number)
                        .font(.body.monospaced())
                        .textContentType(.creditCardNumber)
                        .autocorrectionDisabled()
                    if let summary {
                        LabeledContent("Network", value: String(localized: summary.network.displayName))
                    }
                }
                Section("Expires") {
                    Picker("Month", selection: $card.expiryMonth) {
                        ForEach(1...12, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                    }
                    Picker("Year", selection: $card.expiryYear) {
                        ForEach(years, id: \.self) { Text(verbatim: String($0)).tag($0) }
                    }
                }
                Section {
                    Toggle("Remember security code", isOn: $keepsSecurityCode)
                    if keepsSecurityCode {
                        SecureField("Security code", text: securityCode)
                    }
                    Picker("Billing address", selection: $card.billingAddressID) {
                        Text("None").tag(UUID?.none)
                        ForEach(addresses) { address in
                            Text(verbatim: address.label.nilIfEmpty ?? address.oneLine).tag(UUID?.some(address.id))
                        }
                    }
                } footer: {
                    CrestFormFootnote("Filling a card always asks for Touch ID or your device password.")
                }
                if !isNew {
                    Section {
                        Button("Delete Card…", role: .destructive) { confirmsDeletion = true }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "New Card" : (card.nickname.nilIfEmpty ?? String(localized: "Card")))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { finish(.cancel) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { finish(.save(saved)) }
                        .disabled(summary?.isValid != true)
                        .accessibilityIdentifier("save-card")
                }
            }
            .confirmationDialog("Delete Card?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { finish(.delete(card.id)) }
                Button("Cancel", role: .cancel) {}
            }
        }
        .crestSheetSize(minWidth: 420, idealWidth: 480, minHeight: 440, idealHeight: 560)
    }

    private var summary: CardSummary? {
        digits.count >= 12 ? browser.cardDetails(digits) : nil
    }

    private var digits: String {
        card.number.filter(\.isNumber)
    }

    private var years: [Int] {
        let now = Calendar.current.component(.year, from: .now)
        return Array(min(now, card.expiryYear)...max(now + 15, card.expiryYear))
    }

    private var securityCode: Binding<String> {
        Binding {
            card.securityCode ?? ""
        } set: {
            card.securityCode = String($0.filter(\.isNumber).prefix(4))
        }
    }

    /// The card as it is kept: the number as digits, and the security code
    /// only when the person asked for it.
    private var saved: CardRecord {
        var record = card
        record.number = digits
        record.securityCode = keepsSecurityCode ? card.securityCode?.nilIfEmpty : nil
        return record
    }
}
