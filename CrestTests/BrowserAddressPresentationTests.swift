import XCTest
@testable import Crest

final class BrowserAddressPresentationTests: XCTestCase {
    func testAddressPresentationPromotesDomainAndSeparatesTheRoute() {
        let presentation = BrowserAddressPresentation(
            "https://www.apple.com/mac/iphone/?model=pro#finish"
        )

        XCTAssertEqual(presentation.domain, "apple.com")
        XCTAssertEqual(presentation.route, "/mac/iphone/?model=pro#finish")
    }

    func testAddressPresentationOmitsARootRoute() {
        let presentation = BrowserAddressPresentation("https://apple.com/")

        XCTAssertEqual(presentation.domain, "apple.com")
        XCTAssertNil(presentation.route)
    }

    func testAddressPresentationKeepsNonURLInputReadable() {
        let presentation = BrowserAddressPresentation("swiftui glass")

        XCTAssertEqual(presentation.domain, "swiftui glass")
        XCTAssertNil(presentation.route)
    }
}
