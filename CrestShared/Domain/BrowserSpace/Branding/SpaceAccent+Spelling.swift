import Foundation

/// TRANSITIONAL until S6.7 makes the accent a fixed set that carries its own
/// stored spelling: the Swift session copy, sync payloads and the JSON session
/// commands still read and write an accent by name. The stored spelling of
/// each accent is its case name, as the core's stored form spells it.
extension SpaceAccent: Codable {
    // MARK: - Variables

    /// The accent's stored spelling.
    var spelling: String { String(describing: self) }

    // MARK: - Initializers

    init(from decoder: any Decoder) throws {
        let spelling = try decoder.singleValueContainer().decode(String.self)
        guard let accent = Self.allCases.first(where: { $0.spelling == spelling }) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath, debugDescription: "No accent is spelled \(spelling)."))
        }
        self = accent
    }

    // MARK: - Actions - Encoding

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(spelling)
    }
}
