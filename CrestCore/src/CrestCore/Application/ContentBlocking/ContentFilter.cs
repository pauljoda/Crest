using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

using static CrestCore.Application.ContentFilterLibrary;

namespace CrestCore.Application;

/// Filter lists compiled by Brave's adblock engine into one immutable filter.
/// A change of lists compiles a new filter; a filter the core saved loads back
/// without compiling, but only into the same library that saved it.
internal sealed class ContentFilter : IDisposable {
    #region Types

    /// What a request fetches, numbered as the library numbers it.
    public enum RequestKind : byte {
        Other = 0,
        Document = 1,
        Subdocument = 2,
        Script = 3,
        Stylesheet = 4,
        Image = 5,
        Font = 6,
        Media = 7,
        XmlHttpRequest = 8,
        WebSocket = 9,
        Ping = 10,
        Object = 11,
        CspReport = 12
    }

    /// A request's HTTP method; `Unknown` matches no `$method` filter.
    public enum RequestMethod : byte {
        Unknown = 0,
        Get = 1,
        Head = 2,
        Post = 3,
        Put = 4,
        Delete = 5,
        Connect = 6,
        Options = 7,
        Patch = 8,
        Other = 9
    }

    /// One network request a page makes, from the document at `SourceUrl`.
    public sealed record Request(string Url, string SourceUrl, RequestKind Kind, RequestMethod Method = RequestMethod.Get);

    /// Filter lists as WebKit content rules, each rule its JSON text: the rules
    /// that block or hide, and the `ignore-previous-rules` exceptions that must
    /// follow them in every compiled list they are split into, since an
    /// exception in one list never reaches another.
    public sealed record ContentRules(IReadOnlyList<string> Rules, IReadOnlyList<string> Exceptions);

    /// What a page hides by the filter's site rules: selectors to hide, the
    /// generic selectors those rules exempt, whether the site turns generic
    /// hiding off altogether, the procedural filters and actions no style
    /// sheet expresses, each as the engine's JSON for a page script to apply,
    /// and the scriptlets to run in the page's own world before its scripts.
    public sealed record PageResources(IReadOnlyList<string> HideSelectors, IReadOnlyList<string> Exceptions, bool GenericHide,
        IReadOnlyList<string> ProceduralActions, string InjectedScript);

    /// A call that uses lists lent to the library.
    private unsafe delegate void LentTexts(Text* texts, nuint count);

    #endregion

    #region Variables

    internal FilterHandle Handle { get; }

    #endregion

    #region Constructors

    private ContentFilter(FilterHandle handle) {
        Handle = handle;
    }

    #endregion

    #region Actions - Compiling

    /// Compiles `lists`, each a filter list's text Crest chose, with
    /// `resources`, the scriptlets and redirect resources as adblock-rust's
    /// JSON. Without resources, a filter that blocks only to serve a
    /// replacement resource is left out, so its request is allowed.
    public static ContentFilter Compile(IReadOnlyList<string> lists, string? resources = null) => Compile(lists, [], resources);

    /// Compiles the lists Crest chose, `chosen`, and the ones the person added
    /// or wrote, `added`, with `resources`. Only the chosen lists may run the
    /// scriptlets uBlock keeps for trusted lists.
    public static unsafe ContentFilter Compile(IReadOnlyList<string> chosen, IReadOnlyList<string> added, string? resources) {
        ArgumentNullException.ThrowIfNull(chosen);
        ArgumentNullException.ThrowIfNull(added);
        RequireCompatibleLibrary();
        FilterHandle handle = null!;
        Lend([.. chosen, .. added], (texts, count) => LendText(resources ?? "", resourceText => {
            Require(crest_content_filter_build_with_resources(texts, count, (nuint)chosen.Count, resourceText, out handle),
                "compile its lists");
            return 0;
        }));
        return new ContentFilter(handle);
    }

    /// The filter `Save` wrote, with `resources`, which a saved filter does
    /// not keep, or null when this library cannot read it, such as one a
    /// previous version saved. Only pass what the core itself saved: the
    /// library trusts its own version's data.
    public static unsafe ContentFilter? Load(ReadOnlySpan<byte> saved, string? resources = null) {
        RequireCompatibleLibrary();
        FilterHandle handle;
        int status;
        fixed (byte* bytes = saved) {
            byte* lent = bytes;
            nuint length = (nuint)saved.Length;
            (status, handle) = LendText(resources ?? "", resourceText => {
                int result = crest_content_filter_load_with_resources(lent, length, resourceText, out var loaded);
                return (result, loaded);
            });
        }
        if (status == Unreadable) {
            handle.Dispose();
            return null;
        }
        Require(status, "load a saved filter");
        return new ContentFilter(handle);
    }

    /// The filter in the form `Load` reads back.
    public unsafe byte[] Save() {
        Allocation buffer = default;
        Require(crest_content_filter_save(Handle, &buffer), "save the filter");
        return Take(ref buffer);
    }

    /// `lists` converted to WebKit content rules.
    public static unsafe ContentRules ContentRulesFor(IReadOnlyList<string> lists) {
        ArgumentNullException.ThrowIfNull(lists);
        RequireCompatibleLibrary();
        byte[] json = [];
        Lend(lists, (texts, count) => {
            Allocation buffer = default;
            Require(crest_content_filter_content_rules(texts, count, &buffer), "convert its lists to content rules");
            json = Take(ref buffer);
        });
        using var converted = JsonDocument.Parse(json);
        return new ContentRules(Texts(converted.RootElement, "rules"), Texts(converted.RootElement, "exceptions"));
    }

    private static IReadOnlyList<string> Texts(JsonElement rules, string name) =>
        [.. rules.GetProperty(name).EnumerateArray().Select(rule => rule.GetRawText())];

    /// Lends `lists` to the library as UTF-8 texts for the call `use` makes.
    private static unsafe void Lend(IReadOnlyList<string> lists, LentTexts use) {
        var encoded = lists.Select(Encoding.UTF8.GetBytes).ToArray();
        var pins = encoded.Select(bytes => GCHandle.Alloc(bytes, GCHandleType.Pinned)).ToArray();
        try {
            var texts = new Text[encoded.Length];
            for (int index = 0; index < encoded.Length; index++)
                texts[index] = new Text { Bytes = (byte*)pins[index].AddrOfPinnedObject(), Length = (nuint)encoded[index].Length };
            fixed (Text* lent = texts) use(lent, (nuint)texts.Length);
        } finally {
            foreach (var pin in pins) pin.Free();
        }
    }

    #endregion

    #region Actions - Matching

    /// Whether this filter blocks `request`.
    public unsafe bool Blocks(Request request) {
        ArgumentNullException.ThrowIfNull(request);
        var url = Encoding.UTF8.GetBytes(request.Url);
        var source = Encoding.UTF8.GetBytes(request.SourceUrl);
        Decision decision = default;
        fixed (byte* urlBytes = url)
        fixed (byte* sourceBytes = source) {
            var lent = new ContentFilterLibrary.Request {
                Url = new Text { Bytes = urlBytes, Length = (nuint)url.Length },
                SourceUrl = new Text { Bytes = sourceBytes, Length = (nuint)source.Length },
                Kind = (byte)request.Kind,
                Method = (byte)request.Method
            };
            Require(crest_content_filter_check(Handle, &lent, &decision), "check a request");
        }
        return decision.Verdict != Allow;
    }

    #endregion

    #region Actions - Hiding

    /// What a page at `url` hides by the filter's site rules.
    public unsafe PageResources ResourcesFor(string url) {
        ArgumentNullException.ThrowIfNull(url);
        var json = LendText(url, text => {
            Allocation buffer = default;
            Require(crest_content_filter_page_resources(Handle, text, &buffer), "describe a page");
            return Take(ref buffer);
        });
        using var resources = JsonDocument.Parse(json);
        var root = resources.RootElement;
        return new PageResources(Strings(root.GetProperty("hide_selectors")), Strings(root.GetProperty("exceptions")),
            root.GetProperty("generichide").GetBoolean(), Strings(root.GetProperty("procedural_actions")),
            root.GetProperty("injected_script").GetString() ?? "");
    }

    /// The generic hide selectors for a page that shows `classes` and `ids`,
    /// leaving out what the page's `exceptions` exempt.
    public unsafe IReadOnlyList<string> HiddenSelectors(IEnumerable<string> classes, IEnumerable<string> ids,
        IEnumerable<string> exceptions) {
        var query = new JsonObject {
            ["classes"] = Array(classes),
            ["ids"] = Array(ids),
            ["exceptions"] = Array(exceptions)
        }.ToJsonString();
        var json = LendText(query, text => {
            Allocation buffer = default;
            Require(crest_content_filter_hidden_selectors(Handle, text, &buffer), "find a page's hidden selectors");
            return Take(ref buffer);
        });
        using var selectors = JsonDocument.Parse(json);
        return Strings(selectors.RootElement);
    }

    private static IReadOnlyList<string> Strings(JsonElement array) =>
        [.. array.EnumerateArray().Select(item => item.GetString() ?? "")];

    private static JsonArray Array(IEnumerable<string> names) => [.. names.Select(name => (JsonNode?)name)];

    #endregion

    #region Mutators

    /// Lets go of this retention; a slot that holds the filter keeps its own.
    public void Dispose() => Handle.Dispose();

    #endregion
}
