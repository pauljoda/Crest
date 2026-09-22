namespace CrestCore.Domain;

/// A saved credential's identity and recency metadata. It never carries the
/// secret. `Username` is only needed where a rule matches accounts; dates are
/// in seconds since 1970.
public sealed record CredentialRecord(Guid Id, string? Username, double UpdatedAt, double? LastUsedAt) {
    #region Variables

    /// The moment the credential was last relevant to the person.
    public double RecencyDate => LastUsedAt ?? UpdatedAt;

    #endregion
}
