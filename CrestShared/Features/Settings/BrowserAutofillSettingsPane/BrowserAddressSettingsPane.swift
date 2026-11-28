import SwiftUI

/// Settings › Autofill › Addresses: the person's addresses, shared by every
/// Space, searchable by any of their words, each opening in an editor, and a
/// way to add one.
struct BrowserAddressSettingsPane<Header: View>: View {
    let browser: BrowserStore
    @ViewBuilder let header: Header

    @State private var addresses: [AddressRecord] = []
    @State private var editing: AddressRecord?
    @State private var errorMessage: String?
    @State private var searchText = ""

    var body: some View {
        BrowserSettingsPane(.passwords) {
            BrowserSettingsPaneNote { header }
            BrowserSettingsSectionSlot(.addresses) {
                Section("Addresses") {
                    if !addresses.isEmpty {
                        CrestSearchField("Search addresses", text: $searchText)
                            .accessibilityIdentifier("address-search")
                    }
                    if !searchText.isEmpty, shownAddresses.isEmpty {
                        Text("No matches").foregroundStyle(.secondary)
                    }
                    ForEach(shownAddresses) { address in
                        Button {
                            editing = address
                        } label: {
                            HStack(spacing: CrestSpacing.medium) {
                                Image(systemName: "house.fill")
                                    .foregroundStyle(CrestBrandTheme.accent)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: CrestFormRowMetrics.titleSpacing) {
                                    Text(verbatim: address.label.nilIfEmpty ?? address.oneLine)
                                        .font(CrestTypography.controlTitle)
                                    Text(verbatim: address.oneLine)
                                        .font(CrestTypography.metadata)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                CrestFormDisclosureChevron()
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("address-row-\(address.id)")
                    }
                    Button("Add Address", systemImage: "plus") {
                        editing = AddressRecord(
                            id: UUID(), label: "", givenName: "", additionalName: "", familyName: "", organization: "",
                            streetLines: [], city: "", region: "", postalCode: "",
                            country: Locale.current.region?.identifier ?? "",
                            phone: "", email: "")
                    }
                    .accessibilityIdentifier("add-address")
                }
            }
            BrowserSettingsPaneNote {
                if let errorMessage {
                    BrowserCredentialErrorSection(message: errorMessage)
                }
            }
        }
        .task { await load() }
        .sheet(item: $editing) { address in
            BrowserAddressEditor(address: address, isNew: !addresses.contains { $0.id == address.id }) { result in
                editing = nil
                Task { await apply(result) }
            }
        }
    }

    /// The addresses whose label, name, organisation, street, city, region,
    /// postal code, country, phone or email holds every word searched for.
    private var shownAddresses: [AddressRecord] {
        let words = searchText.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return addresses }
        return addresses.filter { address in
            let text =
                ([
                    address.label, address.givenName, address.additionalName, address.familyName, address.organization,
                    address.city, address.region, address.postalCode, address.country, address.phone, address.email,
                    Locale.current.localizedString(forRegionCode: address.country) ?? "",
                ] + address.streetLines).joined(separator: " ")
            return words.allSatisfy { text.localizedStandardContains($0) }
        }
    }

    private func load() async {
        do {
            addresses = try await browser.savedAddresses()
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Crest couldn’t read your addresses.")
        }
    }

    private func apply(_ result: BrowserAutofillEditResult<AddressRecord>) async {
        do {
            switch result {
            case .save(let address): try await browser.saveAddress(address)
            case .delete(let id): try await browser.deleteAddress(id: id)
            case .cancel: return
            }
            await load()
        } catch {
            errorMessage = String(localized: "Crest couldn’t save that address.")
        }
    }
}

/// What an address or card editor ended with.
enum BrowserAutofillEditResult<Record> {
    case save(Record)
    case delete(UUID)
    case cancel
}

/// One address: a label, then its fields, and Delete for a saved one.
struct BrowserAddressEditor: View {
    @State var address: AddressRecord
    let isNew: Bool
    let finish: (BrowserAutofillEditResult<AddressRecord>) -> Void

    @State private var confirmsDeletion = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Label", text: $address.label, prompt: Text("Home"))
                }
                Section("Name") {
                    TextField("First name", text: $address.givenName)
                    TextField("Middle name", text: $address.additionalName)
                    TextField("Last name", text: $address.familyName)
                    TextField("Organisation", text: $address.organization)
                }
                Section("Address") {
                    TextField("Street", text: line(0))
                    TextField("Apartment, suite, etc.", text: line(1))
                    TextField("City", text: $address.city)
                    TextField("State or region", text: $address.region)
                    TextField("Postal code", text: $address.postalCode)
                    Picker("Country or region", selection: $address.country) {
                        Text("None").tag("")
                        ForEach(Self.regions, id: \.code) { region in
                            Text(region.name).tag(region.code)
                        }
                    }
                }
                Section("Contact") {
                    TextField("Phone", text: $address.phone)
                        .textContentType(.telephoneNumber)
                    TextField("Email", text: $address.email)
                        .textContentType(.emailAddress)
                }
                if !isNew {
                    Section {
                        Button("Delete Address…", role: .destructive) { confirmsDeletion = true }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "New Address" : (address.label.nilIfEmpty ?? String(localized: "Address")))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { finish(.cancel) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { finish(.save(trimmed)) }
                        .accessibilityIdentifier("save-address")
                }
            }
            .confirmationDialog("Delete Address?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { finish(.delete(address.id)) }
                Button("Cancel", role: .cancel) {}
            }
        }
        .crestSheetSize(minWidth: 420, idealWidth: 480, minHeight: 460, idealHeight: 600)
    }

    /// The street line at `index`, as a field edits it.
    private func line(_ index: Int) -> Binding<String> {
        Binding {
            address.streetLines.indices.contains(index) ? address.streetLines[index] : ""
        } set: { value in
            while address.streetLines.count <= index { address.streetLines.append("") }
            address.streetLines[index] = value
        }
    }

    /// The address with blank street lines left out and every field within
    /// the core's limits.
    private var trimmed: AddressRecord {
        var record = address
        record.streetLines = Array(
            record.streetLines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                .prefix(AddressRecord.maximumStreetLines))
        return record
    }

    /// Every country and region, by its name in the person's language.
    private static let regions: [(code: String, name: String)] = Locale.Region.isoRegions
        .filter { $0.identifier.count == 2 && $0.identifier.allSatisfy(\.isLetter) }
        .compactMap { region in
            Locale.current.localizedString(forRegionCode: region.identifier).map { (region.identifier, $0) }
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}
