@MainActor
struct MobileOnboardingDraftPersistence {
    private let loadPlan: () -> BrowserManualSetupPlan?
    private let savePlan: (BrowserManualSetupPlan) -> Void
    private let clearPlan: () -> Void

    init(
        load: @escaping () -> BrowserManualSetupPlan?,
        save: @escaping (BrowserManualSetupPlan) -> Void,
        clear: @escaping () -> Void
    ) {
        loadPlan = load
        savePlan = save
        clearPlan = clear
    }

    func load() -> BrowserManualSetupPlan? {
        loadPlan()
    }

    func plan(for request: BrowserOnboardingRequest, existing: BrowserSession) -> BrowserManualSetupPlan {
        var plan = (request.entryPoint == .rerun ? nil : load()) ?? BrowserManualSetupPlan(existing: existing)
        plan.reconcile(with: existing)
        plan.discardAddedTabs()
        if plan.spaces.isEmpty, let spaceID = try? plan.addSpace() {
            plan.setSpaceIdentity(name: "Personal", symbol: "person.fill", for: spaceID)
        }
        return plan
    }

    func save(_ plan: BrowserManualSetupPlan) {
        savePlan(plan)
    }

    func clear() {
        clearPlan()
    }

    static let live = Self(
        load: { BrowserManualSetupDraftStore.load() },
        save: { BrowserManualSetupDraftStore.save($0) },
        clear: { BrowserManualSetupDraftStore.clear() }
    )

    static let preview = Self(load: { nil }, save: { _ in }, clear: {})
}
