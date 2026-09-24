using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// The first session a file gets: the one the installed release kept in its
/// defaults, with the journal and the selection it kept, or the seed that
/// stands in when there is none to carry.
internal sealed record FirstSession(SessionState Session, NativeSyncJournal? Journal, JsonObject? LegacySelection,
    IReadOnlyList<TabFavicon> Favicons, bool RequestsCloudRecovery) {
    #region Variables

    private static readonly JsonDocumentOptions DocumentOptions = new() { MaxDepth = 64 };

    #endregion

    #region Actions - Choosing

    /// The session `adoption` gives a file. The installed session is its
    /// history-free core with each Space's history beside it, or, before that
    /// split, one whole graph with history and images inside it. One that does
    /// not decode is left alone: the seed stands in, and the cloud is asked for
    /// a full pull instead of learning that every real Space was deleted. The
    /// journal goes only with an installed session. Throws `Rejected` when that
    /// journal does not decode, or when the seed does not.
    public static FirstSession For(AdoptLegacySession adoption) {
        ArgumentNullException.ThrowIfNull(adoption);
        var installed = adoption.Installed;
        if (installed.Core is { } core) {
            var history = installed.History.ToDictionary(part => part.SpaceId, part => part.Entries);
            return Installed(core, installed.Journal, space => history.TryGetValue(space.Id, out var entries)
                ? StoredSessionCodec.DecodeInstalledHistory(entries) : []) ?? Seed(adoption.Seed, requestsCloudRecovery: true);
        }
        if (installed.WholeGraph is { } wholeGraph)
            return Installed(wholeGraph, installed.Journal, space => space.History) ?? Seed(adoption.Seed, requestsCloudRecovery: true);
        return Seed(adoption.Seed, requestsCloudRecovery: false);
    }

    /// The installed session with each Space's history from `history`, or null
    /// when the bytes are not a session this build can read.
    private static FirstSession? Installed(byte[] bytes, byte[]? journal,
        Func<SpaceState, IReadOnlyList<HistoryEntryState>> history) {
        if (Decode(bytes) is not { } decoded) return null;
        var session = decoded.Session with {
            Spaces = [.. decoded.Session.Spaces.Select(space => space with { History = history(space) })]
        };
        return new(session, journal is null ? null : StoredSession.DecodeJournal(journal),
            StoredSession.DecodeLegacySelection(decoded.Document), decoded.Favicons, RequestsCloudRecovery: false);
    }

    private static FirstSession Seed(byte[] bytes, bool requestsCloudRecovery) =>
        Decode(bytes) is { } seed
            ? new(seed.Session, Journal: null, LegacySelection: null, seed.Favicons, requestsCloudRecovery)
            : throw new Rejected(new StorageUnreadable(StorageFailure.Damaged));

    private static (JsonObject Document, SessionState Session, IReadOnlyList<TabFavicon> Favicons)? Decode(byte[] bytes) {
        try {
            if (bytes.Length is 0 or > NativeSessionAuthority.MaximumBytes
                || JsonNode.Parse(bytes, documentOptions: DocumentOptions) is not JsonObject document) return null;
            return (document, StoredSessionCodec.DecodeInstalledSession(document), StoredSessionCodec.DecodeInlineFavicons(document));
        } catch (Exception error) when (StoredSession.IsUndecodable(error)) {
            return null;
        }
    }

    #endregion
}
