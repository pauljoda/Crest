import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionDiscoveryModelTests: XCTestCase {
    func testUnpackedChoiceRoutesThroughTheSharedWorkflowForTheSameSpace()
        throws
    {
        let space = try XCTUnwrap(BrowserSession.preview.spaces.first)
        let extensionsModel = BrowserExtensionsModel(
            space: space,
            extensionControllerPool: BrowserExtensionControllerPool()
        )
        let discoveryModel = BrowserExtensionDiscoveryModel(
            extensionsModel: extensionsModel
        )

        discoveryModel.chooseUnpackedExtension()

        XCTAssertTrue(extensionsModel.isChoosingExtension)
        XCTAssertEqual(discoveryModel.extensionsModel.space.id, space.id)
    }

    func testSafariInspectionFailureStaysInTheMacDiscoveryWorkflow()
        async
        throws
    {
        let space = try XCTUnwrap(BrowserSession.preview.spaces.first)
        let extensionsModel = BrowserExtensionsModel(
            space: space,
            extensionControllerPool: BrowserExtensionControllerPool()
        )
        let discoveryModel = BrowserExtensionDiscoveryModel(
            extensionsModel: extensionsModel
        )

        await discoveryModel.inspectSafariApplication(
            from: .failure(DiscoveryFailure.rejected)
        )

        XCTAssertEqual(
            discoveryModel.operationFailure?.message,
            "Rejected test application"
        )
        XCTAssertNil(extensionsModel.operationFailure)
        XCTAssertFalse(discoveryModel.isInspectingApplication)
    }

    private enum DiscoveryFailure: LocalizedError {
        case rejected

        var errorDescription: String? {
            "Rejected test application"
        }
    }
}
