import Foundation

// MARK: - Types

/// What a form message carries, as decoded once from the content script,
/// before its event judges whether the message keeps its contract. A field
/// that is present but not valid is told apart from one the message left out.
struct BrowserCredentialFormFields: Sendable {
    let formID: String?
    let readingID: Int?
    let fields: [FormField]?
    let focusedField: Int?
    let values: [Int: String]?
    let submission: FormSubmission?
    let key: BrowserCredentialPopupKey?
    let isTrustedUserEvent: Bool
    let hasVisiblePasswordField: Bool?
    let fieldRect: BrowserCredentialFieldRect?
    let fieldRectInTopViewport: Bool
    let containsKey: Bool
    let containsFields: Bool
    let containsFocusedField: Bool
    let containsValues: Bool
    let containsSubmission: Bool

    var hasInvalidFields: Bool { containsFields && fields == nil }
    var hasInvalidValues: Bool { containsValues && values == nil }

    /// Whether every value belongs to one of the message's fields.
    var valuesBelongToFields: Bool {
        guard let values, let fields else { return false }
        let indices = Set(fields.map(\.index))
        return values.keys.allSatisfy(indices.contains)
    }

    /// Whether the message carries a value for any password field.
    var carriesPassword: Bool {
        guard let values, let fields else { return false }
        return fields.contains { $0.inputType == .password && values[$0.index] != nil }
    }
}

/// A narrowly validated message from Crest's isolated content world. It
/// deliberately cannot be encoded, and its textual representations never
/// include a value the page's fields held.
struct BrowserCredentialFormMessage: Sendable, Decodable, CustomStringConvertible, CustomDebugStringConvertible {
    // MARK: - Types

    /// One input as the content script describes it.
    private struct WireField: Decodable {
        let index: Int
        let type: String
        let autocomplete: String?
        let name: String?
        let id: String?
        let label: String?
        let placeholder: String?
        let visible: Bool
        let hasValue: Bool
        let entered: Bool
        let minLength: Int?
        let maxLength: Int?
        let passwordRules: String?
    }

    /// How the content script says a form was sent.
    private struct WireSubmission: Decodable {
        let trigger: String
        let inForm: Bool
        let label: String?
    }

    // MARK: - Static Variables

    static let contractVersion = 2
    private static let maximumFormIDLength = 256
    private static let maximumFields = 40
    private static let maximumTextLength = 256
    private static let maximumRulesLength = 1_024
    private static let maximumValueLength = 1_024
    private static let maximumPasswordLength = 16_384

    // MARK: - Variables

    let event: BrowserCredentialFormEvent
    let formID: String?

    /// The page script's reading of the form's fields this message describes,
    /// which a fill names so it lands in those fields.
    let readingID: Int?

    /// The form's inputs, as the core reads them, in the order the page shows them.
    let fields: [FormField]

    /// The index of the field a focus came from.
    let focusedField: Int?

    /// The values the person's fields held, by field index: every one when
    /// the form was sent, and none of its passwords on a focus.
    let values: [Int: String]

    /// How a sent form was sent.
    let submission: FormSubmission?

    /// The key the page held back for Crest's popup.
    let key: BrowserCredentialPopupKey?
    let isTrustedUserEvent: Bool
    let hasVisiblePasswordField: Bool?

    /// Where the focused field sits in its frame's viewport, where the page
    /// reported it. Optional on a focus: a field the bridge cannot measure
    /// still deserves a prompt, just not an anchored one.
    let fieldRect: BrowserCredentialFieldRect?

    /// Whether `fieldRect` is in the top page's viewport: a frame the top
    /// page can reach adds its own place in the page to its field's.
    let fieldRectInTopViewport: Bool

    var description: String {
        "BrowserCredentialFormMessage(event: \(event.name), formID: \(formID ?? "none"), fields: \(fields.count), values: <redacted>)"
    }

    var debugDescription: String { description }

    private enum CodingKeys: String, CodingKey {
        case version
        case event
        case formID
        case readingID
        case fields
        case focusedField
        case values
        case submission
        case key
        case trusted
        case hasVisiblePasswordField
        case fieldRect
        case topViewport
    }

    // MARK: - Initializers

    /// The message a script message's body carries, decoded once; nil for a
    /// body that breaks the contract.
    init?(body: Any) {
        guard JSONSerialization.isValidJSONObject(body),
            let data = try? JSONSerialization.data(withJSONObject: body),
            let message = try? JSONDecoder().decode(Self.self, from: data)
        else {
            return nil
        }
        self = message
    }

    /// Decodes the message and holds it to its event's contract. A field of
    /// the wrong type reads as present but invalid, as an unreadable one.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .version) == Self.contractVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version, in: container, debugDescription: "Unsupported form message version.")
        }
        let event = try container.decode(BrowserCredentialFormEvent.self, forKey: .event)
        let fields = (try? container.decodeIfPresent([WireField].self, forKey: .fields)).flatMap(Self.decodedFields)
        let fieldMessage = BrowserCredentialFormFields(
            formID: Self.text(.formID, in: container, maximumLength: Self.maximumFormIDLength),
            readingID: (try? container.decodeIfPresent(Int.self, forKey: .readingID)).flatMap { $0 > 0 ? $0 : nil },
            fields: fields,
            focusedField: try? container.decodeIfPresent(Int.self, forKey: .focusedField),
            values: (try? container.decodeIfPresent([String: String].self, forKey: .values))
                .flatMap { Self.decodedValues($0, fields: fields) },
            submission: (try? container.decodeIfPresent(WireSubmission.self, forKey: .submission))
                .flatMap(Self.decodedSubmission),
            key: try? container.decodeIfPresent(BrowserCredentialPopupKey.self, forKey: .key),
            isTrustedUserEvent: (try? container.decodeIfPresent(Bool.self, forKey: .trusted)) ?? false,
            hasVisiblePasswordField: try? container.decodeIfPresent(Bool.self, forKey: .hasVisiblePasswordField),
            fieldRect: try? container.decodeIfPresent(BrowserCredentialFieldRect.self, forKey: .fieldRect),
            fieldRectInTopViewport: (try? container.decodeIfPresent(Bool.self, forKey: .topViewport)) ?? false,
            containsKey: container.contains(.key),
            containsFields: container.contains(.fields),
            containsFocusedField: container.contains(.focusedField),
            containsValues: container.contains(.values),
            containsSubmission: container.contains(.submission))
        guard event.accepts(fieldMessage) else {
            throw DecodingError.dataCorruptedError(
                forKey: .event, in: container, debugDescription: "The message breaks its event's contract.")
        }

        self.event = event
        formID = fieldMessage.formID
        readingID = fieldMessage.readingID
        self.fields = fieldMessage.fields ?? []
        focusedField = fieldMessage.focusedField
        values = fieldMessage.values ?? [:]
        submission = fieldMessage.submission
        key = fieldMessage.key
        isTrustedUserEvent = fieldMessage.isTrustedUserEvent
        hasVisiblePasswordField = fieldMessage.hasVisiblePasswordField
        fieldRect = fieldMessage.fieldRect
        fieldRectInTopViewport = fieldMessage.fieldRectInTopViewport
    }

    // MARK: - Actions - Reading

    /// The value of the field at `index`, if it held one.
    func value(at index: Int?) -> String? {
        index.flatMap { values[$0] }
    }

    /// The field at `index`, if the message describes it.
    func field(at index: Int?) -> FormField? {
        index.flatMap { index in fields.first { $0.index == index } }
    }

    // MARK: - Actions - Decoding

    /// The fields the script described, each index once and in order, or nil
    /// for a list that breaks that.
    private static func decodedFields(_ wire: [WireField]) -> [FormField]? {
        guard (1...maximumFields).contains(wire.count),
            wire.enumerated().allSatisfy({ $0.offset == $0.element.index })
        else { return nil }
        return wire.map { field in
            FormField(
                index: field.index, inputType: FormInputType.named(field.type) ?? .other,
                autocomplete: clipped(field.autocomplete), name: clipped(field.name), idAttribute: clipped(field.id),
                label: clipped(field.label), placeholder: clipped(field.placeholder), isVisible: field.visible,
                hasValue: field.hasValue, enteredByPerson: field.entered,
                minLength: field.minLength.flatMap(length), maxLength: field.maxLength.flatMap(length),
                passwordRules: field.passwordRules.flatMap { $0.count <= maximumRulesLength ? $0 : nil })
        }
    }

    /// The values by field index, or nil when any is not a field's. A value
    /// too long to be a username or password is left out, as unavailable.
    private static func decodedValues(_ wire: [String: String], fields: [FormField]?) -> [Int: String]? {
        guard let fields else { return nil }
        var values: [Int: String] = [:]
        for (key, value) in wire {
            guard let index = Int(key), let field = fields.first(where: { $0.index == index }) else { return nil }
            guard !value.isEmpty,
                value.count <= (field.inputType == .password ? maximumPasswordLength : maximumValueLength)
            else { continue }
            values[index] = field.inputType == .password ? value : value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return values
    }

    private static func decodedSubmission(_ wire: WireSubmission) -> FormSubmission? {
        SubmitTrigger.named(wire.trigger).map {
            FormSubmission(trigger: $0, inFormElement: wire.inForm, controlLabel: clipped(wire.label))
        }
    }

    private static func clipped(_ text: String?) -> String {
        String((text ?? "").prefix(maximumTextLength))
    }

    /// A length limit as the page gave it; the core refuses one it can't meet.
    private static func length(_ value: Int) -> Int? {
        value >= 0 ? value : nil
    }

    private static func text(
        _ key: CodingKeys, in container: KeyedDecodingContainer<CodingKeys>, maximumLength: Int
    ) -> String? {
        guard let value = try? container.decodeIfPresent(String.self, forKey: key) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumLength else { return nil }
        return trimmed
    }
}
