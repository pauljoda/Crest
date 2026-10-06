using System.Text.Json;
using System.Text.RegularExpressions;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// The extensions a Chromium profile has installed from the Chrome Web Store,
/// read from the `extensions.settings` its `Secure Preferences` and
/// `Preferences` files keep for each extension, and from the extension's own
/// manifest for a name the settings do not spell out. Those turned off, built
/// in, loaded from a folder, or that are themes or apps are left out, as
/// Crest installs only what the Web Store gives it by identifier.
internal static partial class ChromiumExtensions {
    #region Static Variables

    /// The most extensions one profile offers.
    public const int MaximumCount = 256;
    /// The largest settings or message file an import reads.
    private const long MaximumBytes = 50L * 1024 * 1024;
    private const long MaximumMessageBytes = 1024 * 1024;
    /// Chrome's `ManifestLocation::kInternal`, where it puts what the person
    /// installed from the Web Store.
    private const long InternalLocation = 1;
    private const string MessagePrefix = "__MSG_";
    private const string MessageSuffix = "__";

    private static readonly string[] SettingsFiles = ["Preferences", "Secure Preferences"];
    private static readonly string[] FallbackLocales = ["en", "en_US", "en_GB"];

    #endregion

    #region Actions - Reading

    /// The Web Store extensions `profile` has installed and turned on, by
    /// name, an extension both settings files hold read as the last of them
    /// spells it.
    public static IReadOnlyList<ImportExtension> Read(ImportFolder profile) {
        Dictionary<string, JsonElement> settings = new(StringComparer.Ordinal);
        List<JsonDocument> documents = [];
        try {
            foreach (string name in SettingsFiles) {
                if (Document(profile, name) is not { } document) continue;
                documents.Add(document);
                var entries = ImportJson.Member(ImportJson.Member(document.RootElement, "extensions"), "settings");
                foreach (var entry in ImportJson.Members(entries))
                    if (IsIdentifier(entry.Name) && entry.Value.ValueKind == JsonValueKind.Object) settings[entry.Name] = entry.Value;
            }
            return [.. settings.Where(entry => IsWebStoreExtension(entry.Value))
                .Select(entry => new ImportExtension(entry.Key, Name(profile, entry.Key, entry.Value)))
                .OrderBy(extension => extension.Name, StringComparer.CurrentCultureIgnoreCase)
                .ThenBy(extension => extension.ExtensionId, StringComparer.Ordinal).Take(MaximumCount)];
        } finally {
            foreach (var document in documents) document.Dispose();
        }
    }

    /// A Web Store identifier: 32 letters from a to p.
    public static bool IsIdentifier(string value) => Identifier().IsMatch(value);

    /// Whether the settings describe an extension the person installed from
    /// the Web Store and has not turned off: an internal install flagged as
    /// from the store, not disabled, and neither a theme nor an app. Chromium
    /// has spelled "disabled" two ways: a `disable_reasons` list with any entry
    /// (the current form, which has no `state`), and an older `state` of zero
    /// or a `disable_reasons` bitmask above zero.
    private static bool IsWebStoreExtension(JsonElement settings) {
        if (ImportJson.Integer(ImportJson.Member(settings, "location")) != InternalLocation) return false;
        if (ImportJson.Flag(ImportJson.Member(settings, "from_webstore")) != true) return false;
        if (ImportJson.Integer(ImportJson.Member(settings, "state")) == 0) return false;
        if (HasDisableReasons(ImportJson.Member(settings, "disable_reasons"))) return false;
        var manifest = ImportJson.Member(settings, "manifest");
        return ImportJson.Member(manifest, "theme") is null && ImportJson.Member(manifest, "app") is null;
    }

    /// Whether `value` names a reason the extension is turned off: a list with
    /// any entry, or a number above zero.
    private static bool HasDisableReasons(JsonElement? value) =>
        ImportJson.Array(value) is { Count: > 0 } || ImportJson.Integer(value) is > 0;

    #endregion

    #region Actions - Names

    /// The name `id` shows: its manifest's, with a message in the manifest's
    /// own language, or `id` itself when nothing names it. The settings keep
    /// a copy of the manifest that may leave out what the extension's own
    /// manifest file says.
    private static string Name(ImportFolder profile, string id, JsonElement settings) {
        var manifest = ImportJson.Member(settings, "manifest");
        string? name = ImportJson.Text(ImportJson.Member(manifest, "name"));
        string? version = ImportJson.Text(ImportJson.Member(manifest, "version"));
        string? locale = ImportJson.Text(ImportJson.Member(manifest, "default_locale"));
        if (name is null || (Message(name) is not null && locale is null)) {
            using var stored = Manifest(profile, id, version);
            name ??= ImportJson.Text(ImportJson.Member(stored?.RootElement, "name"));
            locale ??= ImportJson.Text(ImportJson.Member(stored?.RootElement, "default_locale"));
        }
        if (name is not null && Message(name) is { } key) name = Localized(profile, id, version, locale, key);
        return name?.Trim() is { Length: > 0 } trimmed ? trimmed : id;
    }

    /// The key of `__MSG_key__`, or null for any other text.
    private static string? Message(string text) =>
        text.Length > MessagePrefix.Length + MessageSuffix.Length && text.StartsWith(MessagePrefix, StringComparison.Ordinal)
            && text.EndsWith(MessageSuffix, StringComparison.Ordinal) ? text[MessagePrefix.Length..^MessageSuffix.Length] : null;

    /// What the message `key` says in `locale`, the extension's default
    /// language, or in English, or null when its files do not say.
    private static string? Localized(ImportFolder profile, string id, string? version, string? locale, string key) {
        if (Installed(profile, id, version) is not { } folder) return null;
        List<string> locales = [];
        if (locale is not null) locales.Add(locale);
        locales.AddRange(FallbackLocales);
        foreach (string candidate in locales.Distinct(StringComparer.Ordinal)) {
            if (IsUnsafe(candidate)) continue;
            using var messages = Read(folder.Child("_locales").Child(candidate), "messages.json", MaximumMessageBytes);
            if (messages is null) continue;
            foreach (var entry in ImportJson.Members(messages.RootElement))
                if (string.Equals(entry.Name, key, StringComparison.OrdinalIgnoreCase)
                    && ImportJson.Text(ImportJson.Member(entry.Value, "message")) is { } message) return message;
        }
        return null;
    }

    #endregion

    #region Actions - Files

    /// The folder holding `version` of `id`, or its last version when
    /// `version` is unknown. Chrome appends `_0` to a version it has seen
    /// before, which the settings leave out.
    private static ImportFolder? Installed(ImportFolder profile, string id, string? version) {
        var versions = profile.Child("Extensions").Child(id).Folders();
        if (version is not null && !IsUnsafe(version))
            foreach (var folder in versions)
                if (folder.Name == version || folder.Name.StartsWith(version + "_", StringComparison.Ordinal)) return folder;
        return versions.Count > 0 ? versions[^1] : null;
    }

    /// Whether `name` could leave the folder it is looked up in.
    private static bool IsUnsafe(string name) =>
        name.Contains('/') || name.Contains('\\') || name.Contains("..", StringComparison.Ordinal);

    private static JsonDocument? Manifest(ImportFolder profile, string id, string? version) =>
        Installed(profile, id, version) is { } folder ? Read(folder, "manifest.json", MaximumMessageBytes) : null;

    private static JsonDocument? Document(ImportFolder profile, string name) => Read(profile, name, MaximumBytes);

    /// The JSON file `name` in `folder`, when it is small enough and is JSON.
    private static JsonDocument? Read(ImportFolder folder, string name, long maximum) {
        if (folder.File(name) is not { } path) return null;
        try {
            return new FileInfo(path).Length > maximum ? null : ImportJson.Parse(File.ReadAllBytes(path));
        } catch (Exception error) when (error is IOException or UnauthorizedAccessException) {
            return null;
        }
    }

    [GeneratedRegex("^[a-p]{32}$", RegexOptions.CultureInvariant)]
    private static partial Regex Identifier();

    #endregion
}
