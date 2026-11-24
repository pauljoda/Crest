using System.Globalization;

namespace CrestCore.Application;

/// A release's version, `MAJOR.MINOR.PATCH`, which orders Crest's releases.
internal readonly record struct ReleaseVersion(int Major, int Minor, int Patch) : IComparable<ReleaseVersion> {
    #region Actions - Reading

    /// The version `text` spells, or null when it spells none.
    public static ReleaseVersion? Read(string text) {
        ArgumentNullException.ThrowIfNull(text);
        var parts = text.Split('.');
        if (parts.Length != 3) return null;
        var numbers = new int[3];
        for (int index = 0; index < parts.Length; index++)
            if (!int.TryParse(parts[index], NumberStyles.None, CultureInfo.InvariantCulture, out numbers[index])) return null;
        return new(numbers[0], numbers[1], numbers[2]);
    }

    #endregion

    #region Actions - Ordering

    public int CompareTo(ReleaseVersion other) => (Major, Minor, Patch).CompareTo((other.Major, other.Minor, other.Patch));

    /// Whether `version` spells a later release than `earlier` does. False
    /// when either spells none.
    public static bool IsLater(string version, string earlier) =>
        Read(version) is { } later && Read(earlier) is { } before && later.CompareTo(before) > 0;

    #endregion
}
