using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

internal static partial class StoredSessionCodec {
    #region Variables

    private const string LegacyTabGroups = "currentTabFolders";
    private const string FaviconData = "faviconData";
    private const string LegacyFolderSymbol = "folder";

    /// The colors of the tab groups releases before folders stored, which
    /// each become the color of the open folder the group turns into.
    private sealed class LegacyTabGroupColor {
        #region Variables

        public static readonly LegacyTabGroupColor Grey = new("grey", new(0.56, 0.56, 0.58));
        public static readonly LegacyTabGroupColor Blue = new("blue", new(0.04, 0.52, 1));
        public static readonly LegacyTabGroupColor Red = new("red", new(1, 0.27, 0.23));
        public static readonly LegacyTabGroupColor Yellow = new("yellow", new(1, 0.84, 0.04));
        public static readonly LegacyTabGroupColor Green = new("green", new(0.19, 0.82, 0.35));
        public static readonly LegacyTabGroupColor Pink = new("pink", new(1, 0.22, 0.37));
        public static readonly LegacyTabGroupColor Purple = new("purple", new(0.75, 0.35, 0.95));
        public static readonly LegacyTabGroupColor Cyan = new("cyan", new(0.39, 0.82, 1));
        public static readonly LegacyTabGroupColor Orange = new("orange", new(0.91, 0.43, 0.23));
        public static IReadOnlyList<LegacyTabGroupColor> All { get; } = [Grey, Blue, Red, Yellow, Green, Pink, Purple, Cyan, Orange];

        public string Name { get; }
        public BrandColor Color { get; }

        #endregion

        #region Constructors

        private LegacyTabGroupColor(string name, BrandColor color) {
            Name = name;
            Color = color;
        }

        #endregion

        #region Actions - Lookup

        /// The stored color, or grey when the group stored one this build cannot name.
        public static LegacyTabGroupColor Named(string? name) => All.FirstOrDefault(color => color.Name == name) ?? Grey;

        #endregion
    }

    #endregion

    #region Actions - Installed releases

    /// A session an installed release kept: the stored format, where each tab
    /// group the releases before folders stored becomes an open folder once.
    /// A group becomes a folder only when its Space has no folder with its
    /// identity and at least one of its tabs is open and in no folder; those
    /// tabs move into it.
    internal static SessionState DecodeInstalledSession(JsonObject document) {
        var session = DecodeSession(document);
        foreach (var group in Items(document[LegacyTabGroups]).Select(Object)) {
            var spaceId = Identity(group[Key.SpaceId]);
            var folderId = Identity(group[Key.FolderId]);
            var members = Items(group[Key.Tabs]).Select(Identity).ToHashSet();
            var spaces = session.Spaces.ToArray();
            int index = Array.FindIndex(spaces, space => space.Id == spaceId);
            if (index < 0 || spaces[index].Folders.Any(folder => folder.Id == folderId)) continue;
            var space = spaces[index];
            bool Joins(TabState tab) => members.Contains(tab.Id) && !tab.Placement.IsDurable && tab.FolderId is null;
            if (!space.Tabs.Any(Joins)) continue;
            var folder = new FolderState(folderId, TabPlacement.Current, Text(group[Key.Title]) ?? UntitledFolder,
                LegacyFolderSymbol, LegacyTabGroupColor.Named(TolerantText(group[Key.Color])).Color,
                IsCollapsed: TolerantFlag(group[Key.IsCollapsed]) ?? false);
            spaces[index] = space with {
                Folders = [.. space.Folders, folder],
                Tabs = [.. space.Tabs.Select(tab => Joins(tab) ? tab with { FolderId = folderId } : tab)]
            };
            session = session with { Spaces = spaces };
        }
        return session;
    }

    /// The images the tabs of a whole-graph session carry inside it. A tab
    /// without an image, or with one that is not base64, carries none.
    internal static IReadOnlyList<TabFavicon> DecodeInlineFavicons(JsonObject document) {
        var favicons = new List<TabFavicon>();
        foreach (var space in Items(document[Key.Spaces]).OfType<JsonObject>())
            foreach (var tab in Items(space[Key.Tabs]).OfType<JsonObject>()) {
                if (TolerantText(tab[FaviconData]) is not { } encoded) continue;
                var image = new byte[encoded.Length];
                if (!Convert.TryFromBase64String(encoded, image, out int length) || length == 0) continue;
                favicons.Add(new TabFavicon(Identity(tab[Key.Id]), image[..length]));
            }
        return favicons;
    }

    /// One Space's history as an installed release kept it beside the session:
    /// the newest entries it may keep, or none when the bytes do not decode.
    internal static IReadOnlyList<HistoryEntryState> DecodeInstalledHistory(ReadOnlySpan<byte> entries) {
        try {
            return JsonNode.Parse(entries, documentOptions: new() { MaxDepth = 64 }) is JsonArray history
                ? [.. history.Take(HistoryPolicy.MaximumEntries).Select(DecodeHistoryEntry)]
                : [];
        } catch (Exception error) when (error is System.Text.Json.JsonException or BrowserRuleException or InvalidOperationException
            or FormatException) {
            return [];
        }
    }

    #endregion
}
