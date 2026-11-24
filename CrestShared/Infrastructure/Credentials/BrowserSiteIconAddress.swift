import Darwin

/// Whether the addresses a host name resolves to are all on the public
/// internet, for site icon requests that must never reach the local network:
/// no loopback, private, shared, link-local, multicast or reserved address,
/// in IPv4 or IPv6, an IPv4 address an IPv6 one carries included.
enum BrowserSiteIconAddress {
    // MARK: - Actions

    /// Whether `host` resolves, and every address it resolves to is public.
    static func allPublic(for host: String) -> Bool {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return false }
        defer { freeaddrinfo(first) }
        var node: UnsafeMutablePointer<addrinfo>? = first
        while let info = node {
            guard let address = info.pointee.ai_addr, isPublic(address) else { return false }
            node = info.pointee.ai_next
        }
        return true
    }

    /// Whether the four bytes of an IPv4 address name a public host.
    static func isPublicIPv4(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 4 else { return false }
        switch (bytes[0], bytes[1]) {
        case (0, _), (10, _), (127, _), (100, 64...127), (169, 254), (172, 16...31), (192, 168), (198, 18...19):
            return false
        case (192, 0) where bytes[2] == 0:
            return false
        default:
            // Multicast and the reserved block above it.
            return bytes[0] < 224
        }
    }

    /// Whether the sixteen bytes of an IPv6 address name a public host.
    static func isPublicIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return false }
        // The unspecified and loopback addresses, and the old IPv4-compatible ones.
        if bytes[0..<15].allSatisfy({ $0 == 0 }) { return false }
        // An IPv4 address carried in IPv6 is judged as itself.
        if bytes[0..<10].allSatisfy({ $0 == 0 }) && bytes[10] == 0xff && bytes[11] == 0xff {
            return isPublicIPv4(Array(bytes[12..<16]))
        }
        // Unique local, link-local and site-local, and multicast.
        if bytes[0] & 0xfe == 0xfc || bytes[0] == 0xff { return false }
        if bytes[0] == 0xfe && bytes[1] & 0x80 == 0x80 { return false }
        return true
    }

    private static func isPublic(_ address: UnsafePointer<sockaddr>) -> Bool {
        switch Int32(address.pointee.sa_family) {
        case AF_INET:
            let bytes = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                withUnsafeBytes(of: $0.pointee.sin_addr) { Array($0) }
            }
            return isPublicIPv4(bytes)
        case AF_INET6:
            let bytes = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                withUnsafeBytes(of: $0.pointee.sin6_addr) { Array($0) }
            }
            return isPublicIPv6(bytes)
        default:
            return false
        }
    }
}
