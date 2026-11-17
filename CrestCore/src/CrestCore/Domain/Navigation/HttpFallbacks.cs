namespace CrestCore.Domain;

/// The https addresses Crest chose for sites a person just opened by typing
/// them without a scheme, each with the http address that loads instead when
/// the https one can't be reached, as other browsers fall back. An address
/// typed with `https://`, and one Crest holds, such as a saved tab or a
/// history entry, never falls back. They live in memory for the loads they
/// start: each is taken by its first failure, and the oldest give way to new
/// ones.
public sealed class HttpFallbacks {
    #region Static Variables

    /// How many typed addresses wait for their loads at once.
    private const int Held = 16;

    #endregion

    #region Variables

    private readonly Lock gate = new();
    private readonly LinkedList<(Uri Https, string Http)> waiting = [];

    #endregion

    #region Actions - Typing

    /// Remembers that `resolution`, what a person typed, opens an https
    /// address Crest chose, so its failure falls back to http.
    public void Opened(AddressResolution resolution) {
        ArgumentNullException.ThrowIfNull(resolution);
        if (resolution.HttpFallback is not { } http || !Uri.TryCreate(resolution.Url, UriKind.Absolute, out var https)) return;
        lock (gate) {
            Forget(https);
            waiting.AddFirst((https, http));
            while (waiting.Count > Held) waiting.RemoveLast();
        }
    }

    /// The http address to load instead of `failedUrl`, which a person typed
    /// without a scheme and https couldn't reach, taken so it falls back once;
    /// null for any other address.
    public string? Take(string? failedUrl) {
        if (!Uri.TryCreate(failedUrl, UriKind.Absolute, out var failed)) return null;
        lock (gate) {
            for (var node = waiting.First; node is not null; node = node.Next) {
                if (node.Value.Https != failed) continue;
                waiting.Remove(node);
                return node.Value.Http;
            }
        }
        return null;
    }

    #endregion

    #region Mutators

    private void Forget(Uri https) {
        for (var node = waiting.First; node is not null; node = node.Next) {
            if (node.Value.Https != https) continue;
            waiting.Remove(node);
            return;
        }
    }

    #endregion
}
