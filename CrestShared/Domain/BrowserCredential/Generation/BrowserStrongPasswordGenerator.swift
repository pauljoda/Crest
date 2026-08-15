import Foundation

/// Produces a high-entropy ASCII password without storing or logging it.
///
/// The four explicit groups guarantee common website requirements. Characters
/// that are frequently confused in proportional fonts are intentionally absent.
enum BrowserStrongPasswordGenerator {
    static let defaultLength = 20
    static let supportedLengths = 16...64

    private static let lowercase = Array("abcdefghijkmnopqrstuvwxyz")
    private static let uppercase = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
    private static let digits = Array("23456789")
    private static let symbols = Array("-_.!@#$%^&*+=")
    private static let groups = [lowercase, uppercase, digits, symbols]
    private static let allCharacters = groups.flatMap { $0 }

    static func generate(length: Int = defaultLength) throws -> String {
        var generator = SystemRandomNumberGenerator()
        return try generate(length: length, using: &generator)
    }

    static func generate<Generator: RandomNumberGenerator>(
        length: Int = defaultLength,
        using generator: inout Generator
    ) throws -> String {
        guard supportedLengths.contains(length) else {
            throw BrowserStrongPasswordGenerationError.invalidLength
        }

        var password = groups.map { characters in
            characters[Int.random(in: characters.indices, using: &generator)]
        }
        while password.count < length {
            password.append(
                allCharacters[Int.random(in: allCharacters.indices, using: &generator)]
            )
        }
        password.shuffle(using: &generator)
        return String(password)
    }
}
