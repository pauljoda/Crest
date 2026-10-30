#if CREST_CHROMIUM_HOST
    import AppKit
    import Foundation

    /// Worker and extension notifications live with their profile while the
    /// app runs. Every delivery and click rechecks the core's access decision.
    @MainActor
    final class ChromiumProfileNotifications {
        // MARK: - Types

        private struct Posted {
            let generation: UUID
            let notification: ProfileNotificationPosted
            /// When it was posted; the oldest leaves first at the cap.
            let order: Int
        }

        // MARK: - Variables

        private let core: CrestCore
        private let center: any BrowserHostedWebNotificationCentering
        private let pages: NativeEnginePages
        private var posted: [String: Posted] = [:]
        private var postings = 0

        // MARK: - Initializers

        init(core: CrestCore, center: any BrowserHostedWebNotificationCentering, pages: NativeEnginePages) {
            self.core = core
            self.center = center
            self.pages = pages
            core.followNotificationAccess(self) { [weak self] in self?.withdrawInaccessible() }
        }

        // MARK: - Actions - Delivery

        func show(_ notification: ProfileNotificationPosted) {
            let identifier = identifier(profileID: notification.profileID, notificationID: notification.notificationID)
            guard allows(notification) else {
                answer(notification, .declined)
                return
            }
            // Nothing reports a notification the person dismissed in
            // Notification Center, so at the cap the oldest makes room rather
            // than every new one being declined until relaunch.
            if posted[identifier] == nil, posted.count >= 256,
                let oldest = posted.min(by: { $0.value.order < $1.value.order })
            {
                decline(oldest.key, oldest.value.generation)
            }
            let generation = UUID()
            if let previous = posted[identifier] {
                remove(identifier, previous.generation)
            }
            postings &+= 1
            posted[identifier] = Posted(generation: generation, notification: notification, order: postings)
            let delivery = BrowserHostedWebNotificationDelivery(
                identifier: systemIdentifier(identifier, generation), title: notification.title,
                body: notification.body, origin: notification.origin, isSilent: notification.silent)
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Revocation or replacement can race system delivery.
                let shown = await center.show(delivery, while: { isCurrent(identifier, generation) }) { [weak self] _ in
                    guard let self, isCurrent(identifier, generation) else { return }
                    posted.removeValue(forKey: identifier)
                    NSApp.activate()
                    answer(notification, .clicked)
                }
                if !shown { decline(identifier, generation) }
            }
        }

        func withdraw(profileID: UUID, notificationID: String) {
            let identifier = identifier(profileID: profileID, notificationID: notificationID)
            guard let item = posted.removeValue(forKey: identifier) else { return }
            remove(identifier, item.generation)
        }

        // MARK: - Actions - Authorization

        private func allows(_ notification: ProfileNotificationPosted) -> Bool {
            (try? core.query(
                ProfileNotificationDisplayCheck(
                    profileID: notification.profileID, origin: notification.origin, source: notification.source)
            ))?.shows == true
        }

        private func isCurrent(_ identifier: String, _ generation: UUID) -> Bool {
            guard let item = posted[identifier], item.generation == generation else { return false }
            return allows(item.notification)
        }

        private func withdrawInaccessible() {
            for (identifier, item) in posted where !allows(item.notification) {
                decline(identifier, item.generation)
            }
        }

        private func decline(_ identifier: String, _ generation: UUID) {
            guard let item = posted[identifier], item.generation == generation else { return }
            posted.removeValue(forKey: identifier)
            answer(item.notification, .declined)
            remove(identifier, generation)
        }

        private func remove(_ identifier: String, _ generation: UUID) {
            let systemIdentifier = systemIdentifier(identifier, generation)
            Task { @MainActor [center] in await center.remove(identifier: systemIdentifier) }
        }

        private func systemIdentifier(_ identifier: String, _ generation: UUID) -> String {
            "\(identifier).\(generation.uuidString)"
        }

        private func answer(_ notification: ProfileNotificationPosted, _ answer: WebNotificationAnswer) {
            pages.request(
                AnswerProfileNotification(
                    profileID: notification.profileID, notificationID: notification.notificationID, answer: answer))
        }

        private func identifier(profileID: UUID, notificationID: String) -> String {
            "profile.\(profileID.uuidString).\(notificationID)"
        }
    }
#endif
