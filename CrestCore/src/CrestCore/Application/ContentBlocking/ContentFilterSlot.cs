using System.Text;

using static CrestCore.Application.ContentFilterLibrary;

namespace CrestCore.Application;

/// Where the core puts the filter in force, for an engine that checks each
/// request itself to check against from any thread, without the core's locks
/// and without managed code. Installing a filter swaps it in; checks already
/// under way finish with the filter they began with. An empty slot allows
/// every request.
internal sealed class ContentFilterSlot : IDisposable {
    #region Variables

    private readonly SlotHandle handle;

    #endregion

    #region Constructors

    public ContentFilterSlot() {
        RequireCompatibleLibrary();
        handle = crest_content_filter_slot_create();
        if (handle.IsInvalid) throw new InvalidOperationException("The content filter could not make a slot.");
    }

    #endregion

    #region Actions - Matching

    /// Whether the filter in force blocks `request`.
    public unsafe bool Blocks(ContentFilter.Request request) {
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
            Require(crest_content_filter_slot_check(handle, &lent, &decision), "check a request");
        }
        return decision.Verdict == Block;
    }

    #endregion

    #region Mutators

    /// Puts `filter` in force, or empties the slot for null. The slot keeps its
    /// own retention, so the caller may dispose `filter` afterwards.
    public void Install(ContentFilter? filter) {
        int status = filter is null
            ? crest_content_filter_slot_empty(handle)
            : crest_content_filter_slot_install(handle, filter.Handle);
        Require(status, "install a filter");
    }

    public void Dispose() => handle.Dispose();

    #endregion
}
