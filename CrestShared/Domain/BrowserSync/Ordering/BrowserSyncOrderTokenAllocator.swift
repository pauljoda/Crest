import Foundation

enum BrowserSyncOrderTokenAllocator {
    static let encodedWidth = 16
    static let maximumEncodedLength = encodedWidth

    static func allocate<ID: Hashable>(
        ids: [ID],
        existingTokens: [ID: String]
    ) throws -> [ID: String] {
        let tokens: [String] = try BrowserCoreSync.evaluate([
            "version": 1, "operation": "order.allocate",
            "tokens": ids.map { existingTokens[$0] as Any? ?? NSNull() }
        ])
        guard tokens.count == ids.count else { throw BrowserSyncError.invalidField("orderTokens") }
        // Projection validates record identities and reports the offending ID.
        // Avoid trapping here before that validation can reject a duplicate.
        return Dictionary(zip(ids, tokens), uniquingKeysWith: { _, last in last })
    }

    static func isValidEncodedToken(_ token: String) -> Bool {
        guard !token.isEmpty,
              token.utf8.count <= maximumEncodedLength else { return false }
        return token.utf8.allSatisfy { byte in
            (48...57).contains(byte)
                || (65...70).contains(byte)
                || (97...102).contains(byte)
        }
    }

    private static func canonicalValue(_ token: String) -> UInt64? {
        guard token.utf8.count == encodedWidth,
              token == token.lowercased(),
              isValidEncodedToken(token),
              let value = UInt64(token, radix: 16),
              encode(value) == token else { return nil }
        return value
    }

    private static func encode(_ value: UInt64) -> String {
        String(format: "%016llx", value)
    }

    private static func compact<ID: Hashable>(_ ids: [ID]) -> [ID: String] {
        let divisor = UInt64(ids.count + 1)
        let step = UInt64.max / divisor
        var result: [ID: String] = [:]
        for (index, id) in ids.enumerated() {
            result[id] = encode(step * UInt64(index + 1))
        }
        return result
    }

    private static func distributedValues(
        count: Int,
        lower: UInt64?,
        upper: UInt64?
    ) -> [UInt64]? {
        guard count > 0 else { return [] }
        let divisor = UInt64(count + 1)
        let distance: UInt64
        switch (lower, upper) {
        case let (.some(lower), .some(upper)):
            guard lower < upper else { return nil }
            distance = upper - lower
        case let (.some(lower), .none):
            distance = UInt64.max - lower
        case let (.none, .some(upper)):
            distance = upper
        case (.none, .none):
            distance = UInt64.max
        }
        let step = distance / divisor
        guard step > 0 else { return nil }

        return (1...count).map { offset in
            let increment = step * UInt64(offset)
            return lower.map { $0 + increment } ?? increment
        }
    }

    private static func longestIncreasingAnchorValues<ID: Hashable>(
        _ candidates: [(desiredIndex: Int, id: ID, value: UInt64)]
    ) -> [Int: UInt64] {
        guard !candidates.isEmpty else { return [:] }
        var tailValues: [UInt64] = []
        var tailCandidateIndices: [Int] = []
        var predecessors = [Int?](repeating: nil, count: candidates.count)

        for candidateIndex in candidates.indices {
            let value = candidates[candidateIndex].value
            let insertionIndex = lowerBound(in: tailValues, for: value)
            if insertionIndex > 0 {
                predecessors[candidateIndex] = tailCandidateIndices[insertionIndex - 1]
            }
            if insertionIndex == tailValues.count {
                tailValues.append(value)
                tailCandidateIndices.append(candidateIndex)
            } else {
                tailValues[insertionIndex] = value
                tailCandidateIndices[insertionIndex] = candidateIndex
            }
        }

        var result: [Int: UInt64] = [:]
        var candidateIndex = tailCandidateIndices.last
        while let current = candidateIndex {
            let candidate = candidates[current]
            result[candidate.desiredIndex] = candidate.value
            candidateIndex = predecessors[current]
        }
        return result
    }

    private static func lowerBound(
        in values: [UInt64],
        for value: UInt64
    ) -> Int {
        var lower = 0
        var upper = values.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if values[middle] < value {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }
}
