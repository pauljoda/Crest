import XCTest

@testable import Crest

/// Site icons are fetched from the sites themselves, so a page's icon link, a
/// redirect or a name that resolves to the local network must never be asked.
final class BrowserSiteIconAddressTests: XCTestCase {
    func testOnlyPublicAddressesAndHostsMayBeAskedForAnIcon() async {
        for local in [
            [10, 0, 0, 1], [127, 0, 0, 1], [192, 168, 1, 1], [172, 16, 0, 1], [169, 254, 1, 1], [100, 64, 0, 1],
            [0, 0, 0, 0], [224, 0, 0, 1], [192, 0, 0, 8], [198, 18, 0, 1],
        ] {
            XCTAssertFalse(BrowserSiteIconAddress.isPublicIPv4(local.map(UInt8.init)), "\(local)")
        }
        XCTAssertTrue(BrowserSiteIconAddress.isPublicIPv4([93, 184, 216, 34]))
        XCTAssertTrue(BrowserSiteIconAddress.isPublicIPv4([172, 32, 0, 1]))

        let loopback6 = [UInt8](repeating: 0, count: 15) + [1]
        let mappedPrivate: [UInt8] = [UInt8](repeating: 0, count: 10) + [0xff, 0xff, 192, 168, 1, 1]
        let mappedPublic: [UInt8] = [UInt8](repeating: 0, count: 10) + [0xff, 0xff, 93, 184, 216, 34]
        let uniqueLocal: [UInt8] = [0xfd] + [UInt8](repeating: 0, count: 14) + [1]
        let linkLocal: [UInt8] = [0xfe, 0x80] + [UInt8](repeating: 0, count: 13) + [1]
        let multicast: [UInt8] = [0xff, 0x02] + [UInt8](repeating: 0, count: 13) + [1]
        let global: [UInt8] = [0x26, 0x06, 0x28, 0x00] + [UInt8](repeating: 0, count: 11) + [1]
        for local in [loopback6, mappedPrivate, uniqueLocal, linkLocal, multicast] {
            XCTAssertFalse(BrowserSiteIconAddress.isPublicIPv6(local), "\(local)")
        }
        XCTAssertTrue(BrowserSiteIconAddress.isPublicIPv6(mappedPublic))
        XCTAssertTrue(BrowserSiteIconAddress.isPublicIPv6(global))

        for host in ["192.168.1.1", "printer.local", "router.lan", "nas.home.arpa", "localhost", "[::1]", "intranet"] {
            XCTAssertFalse(BrowserSiteIconStore.namesPublicHost(host), host)
        }
        XCTAssertTrue(BrowserSiteIconStore.namesPublicHost("www.example.com"))
        // A public-looking name for a local address is refused once resolved.
        let refusedLoopback = await BrowserSiteIconStore.mayFetch(URL(string: "https://0x7f.1/favicon.ico"))
        XCTAssertFalse(refusedLoopback)
        let refusedScheme = await BrowserSiteIconStore.mayFetch(URL(string: "ftp://www.example.com/favicon.ico"))
        XCTAssertFalse(refusedScheme)
    }
}
