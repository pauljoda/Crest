#if DEBUG || CREST_PERFORMANCE_HARNESS
    import Foundation

    /// S6.4 spike, DEBUG and performance builds only: a kind of view the spike
    /// sidebar draws.
    enum ReadModelSpikeBody: String, CaseIterable {
        case list
        case sectionHeader
        /// The rows of one list the core publishes: a section's top level or
        /// a folder's inside.
        case section
        case row
        case header
        case switcher
        case segment
    }

    #if CREST_PERFORMANCE_HARNESS
        /// S6.4 spike, performance builds only: the spike views' body
        /// evaluations, by kind, since the last reset, which the Release run
        /// reads to check the tripwires' model of SwiftUI against SwiftUI.
        @MainActor
        enum ReadModelSpikeBodyCount {
            private(set) static var counts: [ReadModelSpikeBody: Int] = [:]

            static func count(_ body: ReadModelSpikeBody) {
                counts[body, default: 0] += 1
            }

            static func reset() {
                counts = [:]
            }
        }
    #endif

    /// S6.4 spike, DEBUG and performance builds only: one kind of change the
    /// spike measures, driven through the core, with the bodies the spike's
    /// criteria allow it to evaluate again and to add.
    @MainActor
    struct ReadModelSpikeEdit {
        // MARK: - Static Variables

        static let titleReport = ReadModelSpikeEdit(name: "E1 title report", allowed: [.row: 2]) { bench, run in
            bench.report(bench.pages[run % bench.pages.count], title: "Title \(run)")
        }
        static let committedNavigation = ReadModelSpikeEdit(name: "E2 committed navigation", allowed: [.row: 3]) {
            bench, run in
            bench.store.finishNavigation(
                of: bench.pages[run % bench.pages.count], to: URL(string: "https://navigated-\(run).example/")!,
                titled: "Navigated \(run)")
        }
        static let startPageNavigation = ReadModelSpikeEdit(
            name: "E2 Start Page to web page", allowed: [.section: 1, .row: 3], mounts: [.row: 1],
            prepare: { bench, _ in
                guard let tabID = bench.store.openSessionTab(.startPage, in: bench.space.id, shouldSelect: false),
                    let page = bench.store.openReportingPage(for: tabID, in: bench.space.id)
                else { preconditionFailure("The spike could not open a Start Page.") }
                bench.startPages.append(page)
            },
            perform: { bench, _ in
                guard let page = bench.startPages.last else { return }
                bench.store.finishNavigation(
                    of: page, to: URL(string: "https://started-\(bench.startPages.count).example/")!,
                    titled: "Started \(bench.startPages.count)")
            })
        static let firstFavicon = ReadModelSpikeEdit(name: "E3 favicon, first", allowed: [.row: 2]) { bench, run in
            bench.showIcon(on: bench.pages[run % bench.pages.count], run: run)
        }
        static let newFavicon = ReadModelSpikeEdit(name: "E3 favicon, replaced", allowed: [.row: 2]) { bench, run in
            bench.showIcon(on: bench.pages[0], run: run + 1)
        }
        static let historyVisit = ReadModelSpikeEdit(name: "E4 history visit", allowed: [:]) { bench, run in
            bench.store.finishNavigation(
                of: bench.visitPage, to: URL(string: "https://visited-\(run).example/")!, titled: "Visited \(run)")
        }
        static let showAnotherTab = ReadModelSpikeEdit(name: "E5 show another tab", allowed: [.row: 2]) {
            bench, run in
            bench.store.activateSessionTab(bench.currentTabs[10 + run % 2].id, in: bench.space.id)
        }
        static let moveWithinSection = ReadModelSpikeEdit(name: "E6 move within section", allowed: [.section: 1]) {
            bench, run in
            let anchor = bench.currentTabs[run.isMultiple(of: 2) ? 1 : 25]
            _ = bench.store.moveSessionTab(
                bench.currentTabs[20].id, in: bench.space.id, to: .current, before: anchor.id)
        }
        static let collapseFolder = ReadModelSpikeEdit(
            name: "E7 collapse folder", allowed: [.row: 1], mounts: [.section: .max, .row: .max]
        ) { bench, run in
            guard let folder = bench.space.folders.models.first(where: { $0.parentID == nil }) else { return }
            bench.store.setFolderCollapsed(folder.id, in: bench.space.id, isCollapsed: run.isMultiple(of: 2))
        }
        static let renameSpace = ReadModelSpikeEdit(name: "E8 rename Space", allowed: [.header: 1, .segment: 1]) {
            bench, run in
            bench.store.updateSpaceIdentity(
                bench.space.id, name: "Renamed \(run)", symbol: bench.space.settings.symbol,
                accent: bench.space.settings.accent)
        }
        static let loadingToggle = ReadModelSpikeEdit(name: "E9 loading toggle", allowed: [.row: 2]) { bench, run in
            bench.report(bench.pages[0], isLoading: run.isMultiple(of: 2))
        }
        static let otherWindowSelection = ReadModelSpikeEdit(name: "E10 selection in window B", allowed: [:]) {
            bench, run in
            bench.other.activateSessionTab(bench.currentTabs[12 + run % 2].id, in: bench.space.id)
        }

        static let all = [
            titleReport, committedNavigation, startPageNavigation, firstFavicon, newFavicon, historyVisit,
            showAnotherTab, moveWithinSection, collapseFolder, renameSpace, loadingToggle, otherWindowSelection,
        ]

        // MARK: - Variables

        let name: String
        /// The bodies of each kind a run may evaluate again; any other kind, none.
        let allowed: [ReadModelSpikeBody: Int]
        /// The bodies of each kind a run may add; with none named, a run adds none.
        let mounts: [ReadModelSpikeBody: Int]
        let prepare: (@MainActor (ReadModelSpikeBench, Int) -> Void)?
        let perform: @MainActor (ReadModelSpikeBench, Int) -> Void

        // MARK: - Initializers

        init(
            name: String, allowed: [ReadModelSpikeBody: Int], mounts: [ReadModelSpikeBody: Int] = [:],
            prepare: (@MainActor (ReadModelSpikeBench, Int) -> Void)? = nil,
            perform: @escaping @MainActor (ReadModelSpikeBench, Int) -> Void
        ) {
            self.name = name
            self.allowed = allowed
            self.mounts = mounts
            self.prepare = prepare
            self.perform = perform
        }
    }
#endif
