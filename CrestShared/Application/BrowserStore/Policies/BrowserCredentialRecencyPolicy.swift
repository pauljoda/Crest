enum BrowserCredentialRecencyPolicy {
    static func isLessRecent(
        _ lhs: CredentialDescriptor,
        _ rhs: CredentialDescriptor
    ) -> Bool {
        let lhsDate = lhs.lastUsedAt ?? lhs.updatedAt
        let rhsDate = rhs.lastUsedAt ?? rhs.updatedAt
        if lhsDate != rhsDate {
            return lhsDate < rhsDate
        }
        return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
    }
}
