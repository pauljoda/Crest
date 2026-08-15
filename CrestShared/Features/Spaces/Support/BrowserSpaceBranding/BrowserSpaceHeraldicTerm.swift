/// A term in Crest's heraldic vocabulary.
///
/// Every one of these names is a design token *and* a visible gallery label, so
/// each carries an English name for the code to reason about and a catalog key
/// for the reader to see. The catalog entries are hand-kept: `titleKey` builds a
/// key from a runtime string, which the compiler cannot extract, so a term added
/// here needs its entry added to `Localizable.xcstrings` by hand.
protocol BrowserSpaceHeraldicTerm {
    /// The English design-token name.
    var title: String { get }
}
