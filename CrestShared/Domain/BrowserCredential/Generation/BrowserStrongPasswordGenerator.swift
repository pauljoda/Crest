import Foundation

/// Produces a high-entropy ASCII password without storing or logging it.
///
/// The portable core owns the recipe: the length and the character groups.
/// The password is drawn here from the system's secure random source, so the
/// secret never leaves the native layer that saves and fills it. One character
/// comes from every group, the rest from all groups, then the order is shuffled.
enum BrowserStrongPasswordGenerator {
    static func generate(length: Int? = nil) throws -> String {
        var generator = SystemRandomNumberGenerator()
        return try generate(length: length, using: &generator)
    }

    static func generate<Generator: RandomNumberGenerator>(
        length: Int? = nil,
        using generator: inout Generator
    ) throws -> String {
        guard let recipe = BrowserCorePolicy.strongPasswordRecipe(length: length) else {
            throw BrowserStrongPasswordGenerationError.unavailable
        }
        let allCharacters = recipe.groups.flatMap { $0 }
        var password = recipe.groups.map { characters in
            characters[Int.random(in: characters.indices, using: &generator)]
        }
        while password.count < recipe.length {
            password.append(
                allCharacters[Int.random(in: allCharacters.indices, using: &generator)]
            )
        }
        password.shuffle(using: &generator)
        return String(password)
    }
}
