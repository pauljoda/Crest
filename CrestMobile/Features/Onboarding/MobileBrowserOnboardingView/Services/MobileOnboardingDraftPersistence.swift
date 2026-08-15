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
