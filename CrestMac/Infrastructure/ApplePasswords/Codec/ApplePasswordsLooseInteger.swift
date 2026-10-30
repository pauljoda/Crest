import Foundation

/// An integer the helper may write as a JSON number or as a string of digits.
struct ApplePasswordsLooseInteger: Decodable, Equatable, Sendable {
    // MARK: - Variables

    let value: Int

    // MARK: - Initializers

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self) {
            value = number
        } else {
            let text = try container.decode(String.self)
            guard let number = Int(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an integer")
            }
            value = number
        }
    }
}
