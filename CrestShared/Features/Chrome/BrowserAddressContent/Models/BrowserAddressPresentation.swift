import Foundation

struct BrowserAddressPresentation: Equatable {
    // MARK: - Variables

    let domain: String
    let route: String?

    // MARK: - Initializers

    init(_ text: String) {
        guard !text.isEmpty,
            let components = URLComponents(string: text),
            let rawHost = components.host,
            !rawHost.isEmpty
        else {
            domain = text.isEmpty ? String(localized: "Search or enter website") : text
            route = nil
            return
        }

        var host = rawHost
        if host.lowercased().hasPrefix("www.") {
            host.removeFirst(4)
        }
        if let port = components.port {
            host += ":\(port)"
        }
        domain = host

        var detail = components.percentEncodedPath
        if detail == "/" { detail = "" }
        if let query = components.percentEncodedQuery, !query.isEmpty {
            detail += "?\(query)"
        }
        if let fragment = components.percentEncodedFragment, !fragment.isEmpty {
            detail += "#\(fragment)"
        }
        route = detail.isEmpty ? nil : (detail.removingPercentEncoding ?? detail)
    }
}
