namespace CrestCore.Contracts;

/// Where the downloads of the Space `SpaceId` go on this device: wherever the
/// person says each time when `AsksWhereToSave`, otherwise into `Folder` when
/// they chose one, otherwise into the device's Downloads folder. The device
/// store keeps them and never syncs them.
public sealed record SpaceDownloadPreferences(Guid SpaceId, bool AsksWhereToSave, DownloadFolder? Folder) {
    #region Variables

    /// Whether the preferences say nothing a Space's downloads would not do
    /// anyway, so the device keeps none for it.
    internal bool IsStandard => !AsksWhereToSave && Folder is null;

    #endregion
}

/// A folder the person chose for downloads: its name, as Settings shows it,
/// and the platform's token that opens it again, which the core keeps as it
/// is and never reads.
public sealed record DownloadFolder(string Name, byte[] Token) {
    #region Actions - Equality

    public bool Equals(DownloadFolder? other) =>
        other is not null && Name == other.Name && Token.AsSpan().SequenceEqual(other.Token);

    public override int GetHashCode() => HashCode.Combine(Name, Token.Length);

    #endregion
}

/// Where each Space's downloads go on this device changed. Spaces that keep
/// the device's Downloads folder are left out.
public sealed record DownloadPreferencesChanged(IReadOnlyList<SpaceDownloadPreferences> Spaces) : Change {
    #region Actions - Equality

    public bool Equals(DownloadPreferencesChanged? other) => other is not null && Spaces.SequenceEqual(other.Spaces);

    public override int GetHashCode() => Spaces.Count;

    #endregion
}
