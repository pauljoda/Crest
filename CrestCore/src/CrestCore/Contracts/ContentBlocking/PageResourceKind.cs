using CrestCore.Application;

namespace CrestCore.Contracts;

/// What an element that loads from an address is, and the kind of request
/// the content filter matches it as. A kind travels as its index in `All`,
/// so `All` is append-only.
public sealed class PageResourceKind {
    #region Static Variables

    /// A frame's document.
    public static readonly PageResourceKind Frame = new(name: "frame", ContentFilter.RequestKind.Subdocument);
    /// An image.
    public static readonly PageResourceKind Image = new(name: "image", ContentFilter.RequestKind.Image);
    /// An embedded object or plug-in.
    public static readonly PageResourceKind Object = new(name: "object", ContentFilter.RequestKind.Object);

    public static IReadOnlyList<PageResourceKind> All { get; } = [Frame, Image, Object];

    #endregion

    #region Variables

    /// The kind's spelling, as a page's cosmetic bridge reports it.
    public string Name { get; }

    /// The request kind the content filter matches an element of this kind as.
    internal ContentFilter.RequestKind RequestKind { get; }

    #endregion

    #region Constructors

    private PageResourceKind(string name, ContentFilter.RequestKind requestKind) {
        Name = name;
        RequestKind = requestKind;
    }

    #endregion

    #region Actions - Lookup

    public static PageResourceKind? Named(string? name) => All.FirstOrDefault(kind => kind.Name == name);

    #endregion
}
