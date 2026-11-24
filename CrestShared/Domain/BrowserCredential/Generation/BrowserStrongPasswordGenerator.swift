import Foundation

/// Produces a high-entropy password without storing or logging it.
///
/// The portable core owns the recipe: how many segments of how many
/// characters, the separator between them, the groups every character comes
/// from, the groups each placed once, and the longest run of one character.
/// The password is drawn here from the system's secure random source, so the
/// secret never leaves the native layer that saves and fills it.
enum BrowserStrongPasswordGenerator {
    /// How many draws may fail the recipe's run limit before generation gives up.
    private static let maximumAttempts = 64

    static func generate(from recipe: StrongPasswordRecipe) throws -> String {
        var generator = SystemRandomNumberGenerator()
        return try generate(from: recipe, using: &generator)
    }

    static func generate<Generator: RandomNumberGenerator>(
        from recipe: StrongPasswordRecipe,
        using generator: inout Generator
    ) throws -> String {
        let characters = Array(recipe.groups.joined())
        let required = recipe.required.map(Array.init)
        let length = recipe.segments * recipe.segmentLength
        guard recipe.segments > 0, recipe.segmentLength > 0, !characters.isEmpty,
            required.allSatisfy({ !$0.isEmpty }), required.count <= length
        else {
            throw BrowserStrongPasswordGenerationError.unavailable
        }
        for _ in 0..<maximumAttempts {
            // The places the required groups take, then every other character
            // drawn so it never makes a run longer than the recipe allows.
            let places = Dictionary(
                uniqueKeysWithValues: zip((0..<length).shuffled(using: &generator), required))
            var body: [Character] = []
            for place in 0..<length {
                let choices = places[place] ?? characters
                let allowed = choices.filter { !extendsRun(body, with: $0, beyond: recipe.maxConsecutive) }
                let pool = allowed.isEmpty ? choices : allowed
                body.append(pool[Int.random(in: pool.indices, using: &generator)])
            }
            guard recipe.maxConsecutive <= 0 || longestRun(in: body) <= recipe.maxConsecutive else { continue }
            return stride(from: 0, to: length, by: recipe.segmentLength)
                .map { String(body[$0..<($0 + recipe.segmentLength)]) }
                .joined(separator: recipe.separator)
        }
        throw BrowserStrongPasswordGenerationError.unavailable
    }

    /// Whether adding `character` after `characters` repeats it more than
    /// `limit` times in a row; never, without a limit.
    private static func extendsRun(_ characters: [Character], with character: Character, beyond limit: Int) -> Bool {
        guard limit > 0, characters.count >= limit else { return false }
        return characters.suffix(limit).allSatisfy { $0 == character }
    }

    private static func longestRun(in characters: [Character]) -> Int {
        var longest = 0
        var run = 0
        var previous: Character?
        for character in characters {
            run = character == previous ? run + 1 : 1
            longest = max(longest, run)
            previous = character
        }
        return longest
    }
}
