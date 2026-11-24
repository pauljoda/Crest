import Foundation

// MARK: - Types

/// A saved payment card as a list shows it, read from its item's open
/// metadata: never its number or security code.
struct BrowserSavedCard: Identifiable, Equatable, Sendable {
    let id: UUID
    let nickname: String
    let network: CardNetwork
    let lastFour: String
    let expiryMonth: Int
    let expiryYear: Int
    let updatedAt: Date

    /// The card as the person names it: its nickname, or its network and
    /// last four.
    var title: String {
        nickname.nilIfEmpty ?? "\(String(localized: network.displayName)) ·••• \(lastFour)"
    }

    var expiry: String {
        String(format: "%02d/%02d", expiryMonth, expiryYear % 100)
    }
}

/// An address or card a sent form proposes to keep, until the person
/// answers. Like a password, it is deliberately not `Codable`.
struct BrowserAutofillSaveCandidate: Identifiable, Equatable, Sendable, CustomStringConvertible {
    let id: UUID
    let address: AddressRecord?
    let card: CardRecord?

    var description: String { "BrowserAutofillSaveCandidate(id: \(id), <redacted>)" }
}

// MARK: - Addresses and payment cards

extension BrowserStore {
    // MARK: - Actions - Addresses

    /// The person's addresses, shared by every Space, by label.
    func savedAddresses() async throws -> [AddressRecord] {
        try await autofillVault.items(of: .address)
            .compactMap { try? Self.autofillDecoder.decode(StoredAddress.self, from: $0.secret).record }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    func saveAddress(_ address: AddressRecord, now: Date = Date()) async throws {
        let item = CredentialKeychainItem(
            account: address.id.uuidString.lowercased(),
            metadata: try Self.autofillEncoder.encode(StoredRecordMetadata(id: address.id, updatedAt: now)),
            secret: try Self.autofillEncoder.encode(StoredAddress(address)),
            isSynchronizable: false)
        try await autofillVault.save(item, of: .address)
    }

    func deleteAddress(id: UUID) async throws {
        try await autofillVault.delete(id: id, of: .address)
    }

    // MARK: - Actions - Cards

    /// The person's payment cards as lists show them, without their numbers.
    func savedCards() async throws -> [BrowserSavedCard] {
        try await autofillVault.summaries(of: .card)
            .compactMap { try? Self.autofillDecoder.decode(StoredCardMetadata.self, from: $0.metadata).card }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// The card `id` with its number, which callers show or fill only after
    /// the person authenticates.
    func card(id: UUID) async throws -> CardRecord? {
        guard let item = try await autofillVault.item(id: id, of: .card) else { return nil }
        return try Self.autofillDecoder.decode(StoredCard.self, from: item.secret).record
    }

    func saveCard(_ card: CardRecord, now: Date = Date()) async throws {
        let summary = cardDetails(card.number)
        let metadata = StoredCardMetadata(
            id: card.id, nickname: card.nickname, network: summary?.network.name ?? "",
            lastFour: summary?.lastFour ?? String(card.number.suffix(4)), expiryMonth: card.expiryMonth,
            expiryYear: card.expiryYear, updatedAt: now)
        let item = CredentialKeychainItem(
            account: card.id.uuidString.lowercased(), metadata: try Self.autofillEncoder.encode(metadata),
            secret: try Self.autofillEncoder.encode(StoredCard(card)), isSynchronizable: false)
        try await autofillVault.save(item, of: .card)
    }

    func deleteCard(id: UUID) async throws {
        try await autofillVault.delete(id: id, of: .card)
    }

    /// The network and last four of `number`, and whether it passes the
    /// network's checks, as the core reads it.
    func cardDetails(_ number: String) -> CardSummary? {
        try? core.query(CardDetails(number: number))
    }

    // MARK: - Actions - Filling

    /// What filling `address` puts into the section of `fields` holding `focused`.
    func addressValues(_ address: AddressRecord, into fields: [FormField], focused: Int) -> [BrowserAutofillValue]? {
        (try? core.query(AddressFill(fields: fields, focused: focused, address: address)))?.values.map {
            BrowserAutofillValue(field: $0.field, value: $0.value)
        }
    }

    /// What filling `card` puts into the section of `fields` holding `focused`.
    func cardValues(_ card: CardRecord, into fields: [FormField], focused: Int) -> [BrowserAutofillValue]? {
        (try? core.query(CardFill(fields: fields, focused: focused, card: card)))?.values.map {
            BrowserAutofillValue(field: $0.field, value: $0.value)
        }
    }

    /// Whether the person already keeps the address or card `candidate`
    /// proposes: the same street and postal code, or the same card number.
    func autofillSaveCandidate(alreadyKept candidate: BrowserAutofillSaveCandidate) async -> Bool {
        guard autofillVault.isAvailable else { return true }
        if let proposed = candidate.address,
            ((try? await savedAddresses()) ?? []).contains(where: {
                $0.streetLines == proposed.streetLines && $0.postalCode == proposed.postalCode
            })
        {
            return true
        }
        if let proposed = candidate.card {
            for summary in (try? await savedCards()) ?? [] where summary.lastFour == String(proposed.number.suffix(4)) {
                if (try? await card(id: summary.id))?.number == proposed.number { return true }
            }
        }
        return false
    }

    // MARK: - Actions - Encoding

    private static let autofillEncoder = JSONEncoder()
    private static let autofillDecoder = JSONDecoder()
}

// MARK: - Stored forms

/// What an address or card item says in the open.
private struct StoredRecordMetadata: Codable {
    let id: UUID
    let updatedAt: Date
}

/// What a card item says in the open: enough to list it, never its number.
private struct StoredCardMetadata: Codable {
    let id: UUID
    let nickname: String
    let network: String
    let lastFour: String
    let expiryMonth: Int
    let expiryYear: Int
    let updatedAt: Date

    var card: BrowserSavedCard? {
        BrowserSavedCard(
            id: id, nickname: nickname, network: CardNetwork.named(network) ?? .unknown, lastFour: lastFour,
            expiryMonth: expiryMonth, expiryYear: expiryYear, updatedAt: updatedAt)
    }
}

/// An address as its item keeps it.
private struct StoredAddress: Codable {
    let id: UUID
    let label: String
    let givenName: String
    let additionalName: String
    let familyName: String
    let organization: String
    let streetLines: [String]
    let city: String
    let region: String
    let postalCode: String
    let country: String
    let phone: String
    let email: String

    init(_ record: AddressRecord) {
        id = record.id
        label = record.label
        givenName = record.givenName
        additionalName = record.additionalName
        familyName = record.familyName
        organization = record.organization
        streetLines = record.streetLines
        city = record.city
        region = record.region
        postalCode = record.postalCode
        country = record.country
        phone = record.phone
        email = record.email
    }

    var record: AddressRecord {
        AddressRecord(
            id: id, label: label, givenName: givenName, additionalName: additionalName, familyName: familyName,
            organization: organization, streetLines: streetLines, city: city, region: region, postalCode: postalCode,
            country: country, phone: phone, email: email)
    }
}

/// A card as its item keeps it.
private struct StoredCard: Codable {
    let id: UUID
    let nickname: String
    let cardholder: String
    let number: String
    let expiryMonth: Int
    let expiryYear: Int
    let securityCode: String?
    let billingAddressID: UUID?

    init(_ record: CardRecord) {
        id = record.id
        nickname = record.nickname
        cardholder = record.cardholder
        number = record.number
        expiryMonth = record.expiryMonth
        expiryYear = record.expiryYear
        securityCode = record.securityCode
        billingAddressID = record.billingAddressID
    }

    var record: CardRecord {
        CardRecord(
            id: id, nickname: nickname, cardholder: cardholder, number: number, expiryMonth: expiryMonth,
            expiryYear: expiryYear, securityCode: securityCode, billingAddressID: billingAddressID)
    }
}
