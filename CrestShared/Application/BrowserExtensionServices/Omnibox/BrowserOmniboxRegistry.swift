import Foundation

/// Maps address-bar keywords to the providers that answer for them.
///
/// One keyword has one owner. Registering a keyword that is already taken
/// replaces the previous owner and reports the displacement, so a caller can
/// tell a genuine re-registration from a collision between two extensions that
/// both want `gh`.
@MainActor
final class BrowserOmniboxRegistry {
    private var providers: [BrowserOmniboxKeyword: any BrowserOmniboxSuggesting] = [:]

    init() {}

    /// Keywords with a live provider, in a stable order.
    var registeredKeywords: [BrowserOmniboxKeyword] {
        providers.keys.sorted()
    }

    /// Registers `provider` under its own keyword.
    ///
    /// - Returns: The provider that previously held the keyword, if any.
    @discardableResult
    func register(
        _ provider: any BrowserOmniboxSuggesting
    ) -> (any BrowserOmniboxSuggesting)? {
        let keyword = provider.descriptor.keyword
        let displaced = providers[keyword]
        providers[keyword] = provider
        return displaced
    }

    /// Removes the provider registered for `keyword`.
    @discardableResult
    func unregister(keyword: BrowserOmniboxKeyword) -> (any BrowserOmniboxSuggesting)? {
        providers.removeValue(forKey: keyword)
    }

    func provider(
        for keyword: BrowserOmniboxKeyword
    ) -> (any BrowserOmniboxSuggesting)? {
        providers[keyword]
    }

    func descriptor(
        for keyword: BrowserOmniboxKeyword
    ) -> BrowserOmniboxDescriptor? {
        providers[keyword]?.descriptor
    }

    /// Parses `text` and resolves the provider it addresses, if any.
    func resolve(
        _ text: String
    ) -> (input: BrowserOmniboxInput, provider: any BrowserOmniboxSuggesting)? {
        guard let input = BrowserOmniboxInput.parse(text),
            let provider = providers[input.keyword]
        else {
            return nil
        }
        return (input, provider)
    }
}
