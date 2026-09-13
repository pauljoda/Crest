import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionPermissionPromptTests: XCTestCase {
    private let firstContext = NSObject()
    private let secondContext = NSObject()

    func testDuplicateRequestsShareOneDecisionAndSettleOnce() {
        let owner = BrowserExtensionPermissionPromptController()
        let key = BrowserExtensionPermissionPromptController.Key(
            context: ObjectIdentifier(firstContext), tab: nil, access: ["host:a"])
        var reply: ((BrowserExtensionPermissionPromptController.Decision) -> Void)?
        var presentations = 0
        var decisions: [BrowserExtensionPermissionPromptController.Decision] = []
        for _ in 0..<6 {
            owner.request(
                key: key, isValid: { true }, completion: { decisions.append($0) },
                present: { finish in
                    presentations += 1
                    reply = finish
                    return {}
                })
        }
        XCTAssertEqual(presentations, 1)
        reply?(.allow)
        reply?(.deny)
        XCTAssertEqual(decisions, Array(repeating: .allow, count: 6))
    }

    func testDifferentOwnersQueueAndOverflowIsRefusedWithoutRetainingMoreWork() {
        let owner = BrowserExtensionPermissionPromptController(maximumWaiters: 2)
        let key = BrowserExtensionPermissionPromptController.Key(
            context: ObjectIdentifier(firstContext), tab: nil, access: ["host:a"])
        var replies: [BrowserExtensionPermissionPromptController.Decision] = []
        let present: BrowserExtensionPermissionPromptController.Present = { _ in {} }
        owner.request(key: key, isValid: { true }, completion: { replies.append($0) }, present: present)
        owner.request(key: key, isValid: { true }, completion: { replies.append($0) }, present: present)
        owner.request(key: key, isValid: { true }, completion: { replies.append($0) }, present: present)
        owner.request(
            key: .init(context: ObjectIdentifier(secondContext), tab: nil, access: key.access), isValid: { true },
            completion: { replies.append($0) }, present: present)
        XCTAssertEqual(replies, [.cancel])
        owner.cancel(context: ObjectIdentifier(firstContext))
        XCTAssertEqual(replies, [.cancel, .cancel, .cancel])
        owner.cancel(context: ObjectIdentifier(secondContext))
        XCTAssertEqual(replies, [.cancel, .cancel, .cancel, .cancel])
    }

    func testNavigationOrRevocationCancelsAndLateAllowCannotGrant() {
        let owner = BrowserExtensionPermissionPromptController()
        var valid = true
        var reply: ((BrowserExtensionPermissionPromptController.Decision) -> Void)?
        var decisions: [BrowserExtensionPermissionPromptController.Decision] = []
        var dismissed = false
        owner.request(
            key: .init(context: ObjectIdentifier(firstContext), tab: nil, access: ["host:a"]), isValid: { valid },
            completion: { decisions.append($0) },
            present: { finish in
                reply = finish
                return { dismissed = true }
            })
        valid = false
        owner.reconcile()
        reply?(.allow)
        XCTAssertTrue(dismissed)
        XCTAssertEqual(decisions, [.cancel])
    }

    func testDecisionRevalidatesBeforeAllowAndCancellationIsOwnerScoped() {
        let owner = BrowserExtensionPermissionPromptController()
        var valid = true
        var reply: ((BrowserExtensionPermissionPromptController.Decision) -> Void)?
        var decisions: [BrowserExtensionPermissionPromptController.Decision] = []
        owner.request(
            key: .init(context: ObjectIdentifier(firstContext), tab: nil, access: ["host:a"]), isValid: { valid },
            completion: { decisions.append($0) },
            present: { finish in
                reply = finish
                return {}
            })
        owner.cancel(context: ObjectIdentifier(secondContext))
        XCTAssertTrue(decisions.isEmpty)
        valid = false
        reply?(.allow)
        XCTAssertEqual(decisions, [.cancel])
    }
    func testDistinctRequestsPresentInOrderAndKeepTheirOwnDecisions() {
        let owner = BrowserExtensionPermissionPromptController()
        var firstReply: ((BrowserExtensionPermissionPromptController.Decision) -> Void)?
        var secondReply: ((BrowserExtensionPermissionPromptController.Decision) -> Void)?
        var results: [BrowserExtensionPermissionPromptController.Decision] = []
        owner.request(
            key: .init(context: ObjectIdentifier(firstContext), tab: nil, access: ["host:a"]), isValid: { true },
            completion: { results.append($0) },
            present: {
                firstReply = $0
                return {}
            })
        owner.request(
            key: .init(context: ObjectIdentifier(firstContext), tab: nil, access: ["permission:tabs"]),
            isValid: { true },
            completion: { results.append($0) },
            present: {
                secondReply = $0
                return {}
            })
        XCTAssertNil(secondReply)
        firstReply?(.allow)
        XCTAssertEqual(results, [.allow])
        XCTAssertNotNil(secondReply)
        secondReply?(.deny)
        XCTAssertEqual(results, [.allow, .deny])
    }

    func testQueueLimitAndOwnerReleaseSettleEveryCallback() {
        var owner: BrowserExtensionPermissionPromptController? = BrowserExtensionPermissionPromptController()
        var canceled = 0
        for index in 0..<20 {
            owner?.request(
                key: .init(context: ObjectIdentifier(firstContext), tab: nil, access: ["host:\(index)"]),
                isValid: { true },
                completion: { if $0 == .cancel { canceled += 1 } }, present: { _ in {} })
        }
        XCTAssertEqual(canceled, 11)
        owner = nil
        XCTAssertEqual(canceled, 20)
    }

    func testNativeDelegateNeverGrantsUndeclaredOrBlockedHosts() async throws {
        let pool = BrowserExtensionControllerPool()
        let space = BrowserSession.preview.spaces[0]
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "Fixtures/SpaceProbeExtension", directoryHint: .isDirectory)
        let host = "https://extension-probe.crest.test/*"
        let context = try await pool.loadExtension(
            at: fixture, extensionID: "permission-delegate", in: space,
            permissionSnapshot: BrowserExtensionInstallationPermissionPolicy.reviewedRequiredAccess(
                permissions: ["storage", "activeTab"], hosts: [host]))
        let controller = try XCTUnwrap(context.webExtensionController)
        let reviewed = try XCTUnwrap(URL(string: "https://extension-probe.crest.test/reviewed"))
        let unrelated = try XCTUnwrap(URL(string: "https://unreviewed.crest.test/private-path"))
        var answers: [Set<URL>] = []
        pool.tabWindowCoordinator.webExtensionController(
            controller, promptForPermissionToAccess: [reviewed, unrelated], in: nil, for: context
        ) { urls, _ in answers.append(urls) }
        XCTAssertEqual(answers, [[reviewed]])
        XCTAssertFalse(context.hasAccess(to: unrelated))
        context.setPermissionStatus(.deniedExplicitly, for: try WKWebExtension.MatchPattern(string: host))
        pool.tabWindowCoordinator.webExtensionController(
            controller, promptForPermissionToAccess: [reviewed], in: nil, for: context
        ) { urls, _ in answers.append(urls) }
        XCTAssertEqual(answers, [[reviewed], []])
        XCTAssertFalse(context.hasAccess(to: reviewed))
        let foreignTab = BrowserExtensionTabAdapter(
            tabID: TabID(), spaceID: SpaceID(), coordinator: pool.tabWindowCoordinator)
        pool.tabWindowCoordinator.webExtensionController(
            controller, promptForPermissions: [.storage], in: foreignTab, for: context
        ) { permissions, _ in XCTAssertTrue(permissions.isEmpty) }
    }

}
