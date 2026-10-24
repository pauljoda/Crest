namespace CrestCore.Contracts;

/// The device's default and website engine choices, and what a page does
/// for protected media its engine cannot play. A null default follows the
/// composition's recommended default. They never become sync records.
public sealed record EnginePreferences(EngineKind? DefaultEngine, IReadOnlyList<SiteEngineRule> Rules,
    ProtectedMediaFallback ProtectedMedia) {
    #region Variables

    public IReadOnlyList<SiteEngineRule> Rules {
        get;
        init => field = [.. value];
    } = [.. Rules];

    #endregion

    #region Actions - Equality

    public bool Equals(EnginePreferences? other) => other is not null
        && DefaultEngine == other.DefaultEngine && Rules.SequenceEqual(other.Rules) && ProtectedMedia == other.ProtectedMedia;

    public override int GetHashCode() => HashCode.Combine(DefaultEngine, Rules.Count, ProtectedMedia);

    #endregion
}
