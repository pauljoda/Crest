import Observation
import WebKit

/// Prepares rule lists and distinguishes protection changes from background refreshes.
@MainActor
@Observable
final class BrowserContentBlockingController {
    private(set) var errorDescription: String?
    @ObservationIgnored private(set) var balancedRuleLists: [WKContentRuleList]?
    @ObservationIgnored private let provider: any BrowserContentRuleListProviding
    @ObservationIgnored private var reconciledState: BrowserContentBlockingSessionState?

    init(provider: any BrowserContentRuleListProviding) {
        self.provider = provider
    }

    func prepare() async {
        guard balancedRuleLists == nil else { return }
        do {
            balancedRuleLists = try await provider.balancedRuleLists()
            errorDescription = nil
        } catch {
            errorDescription = error.localizedDescription
        }
    }

    func invalidateRuleLists() {
        balancedRuleLists = nil
    }

    func reconcile(in session: BrowserSession) async -> BrowserContentBlockingUpdate {
        let state = BrowserContentBlockingSessionState(session: session)
        if state.policiesBySpaceID.values.contains(.balanced) {
            await prepare()
        }
        let update = BrowserContentBlockingUpdate(state: state, previousState: reconciledState)
        reconciledState = state
        return update
    }

    func ruleLists(for policy: BrowserContentBlockingPolicy) -> [WKContentRuleList] {
        policy == .balanced ? balancedRuleLists ?? [] : []
    }
}
