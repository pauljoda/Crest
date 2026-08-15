import Foundation

extension BrowserSession {
    mutating func addSpace() {
        let number = spaces.count + 1
        let space = Self.makeBlankSpace(number: number)
        spaces.append(space)
        selectedSpaceID = space.id
    }

    @discardableResult
    mutating func removeSpace(_ spaceID: SpaceID) -> BrowserSpace? {
        guard spaces.count > 1,
              let index = spaces.firstIndex(where: { $0.id == spaceID }) else {
            return nil
        }
        let wasSelected = selectedSpaceID == spaceID
        let removed = spaces.remove(at: index)
        if wasSelected {
            selectedSpaceID = spaces[min(index, spaces.index(before: spaces.endIndex))].id
        }
        if defaultSpaceID == spaceID {
            defaultSpaceID = selectedSpaceID
        }
        ensureSelection(in: selectedSpaceID)
        return removed
    }

    mutating func updateSpaceAccessPolicy(
        _ accessPolicy: BrowserSpaceAccessPolicy,
        in spaceID: SpaceID
    ) {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }) else { return }
        spaces[spaceIndex].accessPolicy = accessPolicy
    }

    mutating func updateSpaceIdentity(
        _ spaceID: SpaceID,
        name: String,
        symbol: String,
        accent: SpaceAccent
    ) {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        spaces[spaceIndex].name = trimmedName.isEmpty ? "Untitled Space" : trimmedName
        spaces[spaceIndex].symbol = trimmedSymbol.isEmpty ? "square.grid.2x2" : trimmedSymbol
        spaces[spaceIndex].accent = accent
    }

    mutating func updateSpaceBranding(
        _ branding: BrowserSpaceBranding,
        in spaceID: SpaceID
    ) {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }) else { return }
        spaces[spaceIndex].branding = branding.normalized()
    }

    mutating func moveSpaces(from source: IndexSet, to destination: Int) {
        let validOffsets = source.filter(spaces.indices.contains)
        guard !validOffsets.isEmpty else { return }
        let movedSpaces = validOffsets.map { spaces[$0] }
        for offset in validOffsets.reversed() {
            spaces.remove(at: offset)
        }
        let removedBeforeDestination = validOffsets.filter { $0 < destination }.count
        let insertionIndex = min(
            max(0, destination - removedBeforeDestination),
            spaces.endIndex
        )
        spaces.insert(contentsOf: movedSpaces, at: insertionIndex)
    }

    mutating func updateCredentialPreferences(
        _ preferences: BrowserCredentialPreferences,
        in spaceID: SpaceID
    ) {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }) else { return }
        spaces[spaceIndex].credentialPreferences = preferences
    }

    mutating func updateBrowsingPreferences(
        _ preferences: BrowserSpaceBrowsingPreferences,
        in spaceID: SpaceID
    ) {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }) else { return }
        spaces[spaceIndex].browsingPreferences = preferences
    }
}
