using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

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

    /// Compiles `lists`, each a filter list's text. A filter that blocks only to
    /// serve a replacement resource is left out, so its request is allowed.
    public static unsafe ContentFilter Compile(IReadOnlyList<string> lists) {
        ArgumentNullException.ThrowIfNull(lists);
        RequireCompatibleLibrary();
        FilterHandle handle = null!;
        Lend(lists, (texts, count) => Require(crest_content_filter_build(texts, count, out handle), "compile its lists"));
        return new ContentFilter(handle);
    }

    /// The filter `Save` wrote, or null when this library cannot read it, such
    /// as one a previous version saved. Only pass what the core itself saved:
    /// the library trusts its own version's data.
    public static unsafe ContentFilter? Load(ReadOnlySpan<byte> saved) {
        RequireCompatibleLibrary();
        FilterHandle handle;
        int status;
        fixed (byte* bytes = saved) status = crest_content_filter_load(bytes, (nuint)saved.Length, out handle);
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

    #region Mutators

    /// Lets go of this retention; a slot that holds the filter keeps its own.
    public void Dispose() => Handle.Dispose();

    #endregion
}
