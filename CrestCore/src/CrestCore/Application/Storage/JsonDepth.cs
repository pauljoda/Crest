using System.Text.Json;

namespace CrestCore.Application;

/// How deep a JSON document Crest reads may nest, by what it holds: a flat
/// preference document, a kept setup draft, a stored session with the records
/// and files it travels in, or another browser's file. A reader refuses
/// anything deeper.
internal sealed class JsonDepth {
    #region Static Variables

    public static readonly JsonDepth Preferences = new(maximum: 8);
    public static readonly JsonDepth Draft = new(maximum: 32);
    public static readonly JsonDepth Session = new(maximum: 64);
    public static readonly JsonDepth Foreign = new(maximum: 512);

    #endregion

    #region Variables

    /// The options a reader parses this kind of document with.
    public JsonDocumentOptions Options { get; }

    #endregion

    #region Constructors

    private JsonDepth(int maximum) {
        Options = new() { MaxDepth = maximum };
    }

    #endregion
}
