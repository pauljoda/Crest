namespace CrestCore.Contracts;

/// What an export of a page's document makes.
public enum PageExportFormat {
    /// A PDF of the document as it prints.
    Pdf,

    /// A PNG of the whole document.
    Png,

    /// An MHTML archive of the document and its resources.
    Mhtml
}
