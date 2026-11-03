using CrestCore.Application;

namespace CrestCore.Contracts;

/// `Provider`, which a person is adding or editing, as the device would
/// search with it once it keeps it, for the editor to show. Nothing is
/// checked: saving it does that. It reads no state, so a host may ask it
/// without an app.
public sealed record SearchProviderPreview(CustomSearchProvider Provider) : StandaloneQuery<SearchProvider> {
    #region Actions - Answering

    internal override SearchProvider Answer(StandaloneContext context) => Provider.Provider;

    #endregion
}
