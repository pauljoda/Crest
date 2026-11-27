using CrestCore.Application;

namespace CrestCore.Contracts;

/// Returns the canonical JavaScript source and metadata for one of Crest's
/// isolated-world content bridges.
public sealed record ContentBridgeSource(ContentBridge Bridge, bool IncludeTestingHooks)
    : StandaloneQuery<ContentBridgeScript> {
    #region Actions - Answering

    internal override ContentBridgeScript Answer(StandaloneContext context) {
        ArgumentNullException.ThrowIfNull(Bridge);
        return Bridge.Script(IncludeTestingHooks);
    }

    #endregion
}
