namespace CrestCore.Contracts;

/// How this device shows pages: the zoom a page starts at, what a page in a
/// tab out of sight keeps doing, and whether pages may draw faster than 60
/// frames a second. The device store keeps them and never syncs them.
public sealed record PagePreferences(double DefaultZoom, BackgroundPageActivity BackgroundActivity, bool AllowsHighFrameRate) {
    #region Static Variables

    /// The zoom a page starts at until the person chooses another.
    public const double StandardZoom = 1;
    /// The least zoom a page starts at.
    public const double MinimumZoom = 0.25;
    /// The most zoom a page starts at.
    public const double MaximumZoom = 5;

    /// The preferences of a device that never chose any.
    public static PagePreferences Default { get; } = new(StandardZoom, BackgroundPageActivity.Suspend, AllowsHighFrameRate: false);

    #endregion

    #region Actions - Rules

    /// `zoom` within the range a page may start at, or the standard zoom for
    /// a value that is not a number.
    internal static double Bounded(double zoom) => double.IsFinite(zoom) ? Math.Clamp(zoom, MinimumZoom, MaximumZoom) : StandardZoom;

    #endregion
}

/// What a page in a tab out of sight keeps doing. The device store spells an
/// activity as its `Name`, so a name never changes, and an activity travels
/// as its index in `All`, so `All` is append-only.
public sealed class BackgroundPageActivity {
    #region Static Variables

    /// The page stops its timers and drawing until it is shown again.
    public static readonly BackgroundPageActivity Suspend = new(name: "suspend");
    /// The page keeps running, its timers slowed.
    public static readonly BackgroundPageActivity Throttle = new(name: "throttle");

    public static IReadOnlyList<BackgroundPageActivity> All { get; } = [Suspend, Throttle];

    #endregion

    #region Variables

    public string Name { get; }

    #endregion

    #region Constructors

    private BackgroundPageActivity(string name) => Name = name;

    #endregion

    #region Actions - Lookup

    public static BackgroundPageActivity? Named(string? name) => All.FirstOrDefault(activity => activity.Name == name);

    #endregion
}

/// This device's page preferences changed.
public sealed record PagePreferencesChanged(PagePreferences Preferences) : Change;
