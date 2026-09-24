/// The core's placement set is the one Swift uses. The stored session spells
/// each placement with its case name.
extension TabPlacement: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let name = try container.decode(String.self)
        guard let placement = Self.allCases.first(where: { String(describing: $0) == name }) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown tab placement \(name)")
        }
        self = placement
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(describing: self))
    }
}
