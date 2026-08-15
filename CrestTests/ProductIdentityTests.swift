import XCTest
@testable import Crest

final class ProductIdentityTests: XCTestCase {
    func testCrestIdentityUsesOneCanonicalNamespaceAcrossProductServices() {
        XCTAssertEqual(ProductIdentity.name, "Crest")
        XCTAssertEqual(ProductIdentity.iconAssetName, "Crest")
        XCTAssertEqual(ProductIdentity.bundleIdentifier, "com.pauldavis.crest")
        XCTAssertEqual(ProductIdentity.serviceNamespace, "com.pauldavis.crest")
        XCTAssertEqual(ProductIdentity.storageDirectoryName, "Crest")
    }
}
