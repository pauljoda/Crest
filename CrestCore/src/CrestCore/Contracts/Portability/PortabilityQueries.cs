namespace CrestCore.Contracts;

/// A file's contents, to save as `Format` names.
public sealed record ExportedDocument(byte[] Contents, ExportFormat Format);

/// What a browser keeps in its data folder: each profile with the files an
/// import reads, and each store of saved passwords, in the order a person
/// meets them there.
public sealed record ImportData(IReadOnlyList<ImportProfile> Profiles, IReadOnlyList<ImportPasswordStore> PasswordStores);

/// A profile's store of saved passwords: `Id`, the name the browser keeps the
/// profile under, the `ProfileName` the person gave it, and the store's path.
public sealed record ImportPasswordStore(string Id, string ProfileName, string Path);

/// One profile of a browser: `Id`, the name the browser keeps it under, the
/// `Name` the person gave it, and the paths of its bookmarks and of its latest
/// session, where it keeps either. A profile keeps at least one. A browser
/// built on Chromium also names the profile's own folder, `ProfilePath`,
/// where its installed extensions are kept.
public sealed record ImportProfile(string Id, string Name, string? BookmarksPath, string? SessionPath, string? ProfilePath = null);

/// The Spaces an import would bring, in order, each with new identities, the
/// way `ImportSpaces` takes them, and the extensions each of those Spaces
/// offers, for those that offer any.
public sealed record ImportedSpaces(IReadOnlyList<SpaceState> Spaces, IReadOnlyList<ImportSpaceExtensions> Extensions);

/// The extensions another browser had installed where the Space `SpaceId`
/// comes from, in the order the browser lists them by name.
public sealed record ImportSpaceExtensions(Guid SpaceId, IReadOnlyList<ImportExtension> Extensions);

/// An extension from the Chrome Web Store: its `ExtensionId`, which is all
/// that is needed to install it again, and the `Name` it shows, or its
/// identifier when it names none.
public sealed record ImportExtension(string ExtensionId, string Name);

#region Models

/// How a review heads each Space an import brings: with the Space's own name
/// and look, or with a plain section label, for a browser whose Spaces are
/// sections of one sidebar.
public enum ImportSpaceHeaderStyle {
    Identity,
    SectionLabel
}

/// `Source`'s `SpaceName` and `NumberedSpaceName` in the person's language, as
/// the platform resolved them, so a Space an import names is stored as the
/// person reads it. `NumberedSpaceName` keeps its `%lld`.
public sealed record ImportSpaceNames(ImportSource Source, string SpaceName, string NumberedSpaceName);

#endregion
