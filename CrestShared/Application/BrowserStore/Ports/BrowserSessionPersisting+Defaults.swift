extension BrowserSessionPersisting {
    /// Saves without a classification, which means rewriting everything.
    func save(_ session: BrowserSession) {
        save(session, scope: .everything)
    }

    func flushPendingSaves() async {}
}
