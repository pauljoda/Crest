namespace CrestCore.Contracts;

/// Why the core cannot read an import.
public enum ImportFlaw {
    /// Its Spaces are not Spaces in the stored format.
    Unreadable,
    /// A Space holds a split whose tabs are not one run of open tabs, which
    /// repair would rewrite.
    MalformedSplit,
    /// A choice names a Space the import does not bring, a Space it brings has
    /// no choice, or two of its Spaces share an identity, so a choice cannot
    /// tell them apart.
    UnpairedChoices
}
