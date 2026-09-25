import Foundation
import Observation
import XCTest

@testable import Crest

/// The S6.4 sidebar spike's tripwires: each kind of change, driven through
/// the core, redraws only the sidebar bodies the spike's criteria allow.
/// `SidebarBodies` reads what each `ReadModelSpike` view's body reads, through
/// the same functions, and hands each child the inputs the view hands it.
extension CoreReadModelTests {
    func testEachChangeRedrawsOnlyTheSidebarBodiesTheSpikeAllows() {
        let bench = ReadModelSpikeBench(session: ReadModelSpikeFixture.composed())
        let bodies = SidebarBodies(mirroring: bench)
        for edit in ReadModelSpikeEdit.all {
            let measured = bodies.measure(edit, on: bench, runs: 2)
            XCTAssertTrue(measured.changed, "\(edit.name) changed nothing.")
            for kind in ReadModelSpikeBody.allCases {
                XCTAssertLessThanOrEqual(
                    measured.maximum(kind), edit.allowed[kind] ?? 0, "\(edit.name) redrew too many \(kind) bodies.")
                if let mounts = edit.mounts[kind] {
                    XCTAssertLessThanOrEqual(measured.maximumMounts(kind), mounts, "\(edit.name) added \(kind) bodies.")
                } else if edit.mounts.isEmpty {
                    XCTAssertEqual(measured.maximumMounts(kind), 0, "\(edit.name) added \(kind) bodies.")
                }
            }
        }
    }
}

// MARK: - Bodies

/// A model of SwiftUI's body evaluations over the spike sidebar. A view reads
/// what its body reads under observation tracking and hands each child its
/// inputs. It evaluates again when something it read changes, or when its
/// parent evaluates and hands it inputs that differ; a child whose inputs are
/// equal is left alone, as SwiftUI leaves it.
@MainActor
final class SidebarBodies {
    // MARK: - Types

    /// A view: its kind, or nil for the root, which is never counted, and
    /// what its body reads, returning its children.
    struct Node {
        let kind: ReadModelSpikeBody?
        let read: @MainActor () -> [Child]
    }

    /// A child a body hands out, by identity, with its inputs.
    struct Child {
        let key: String
        let input: AnyEquatable
        let node: Node
    }

    private final class Mounted {
        var node: Node
        var input: AnyEquatable
        let depth: Int
        var children: [String] = []
        var generation = 0

        init(node: Node, input: AnyEquatable, depth: Int) {
            self.node = node
            self.input = input
            self.depth = depth
        }
    }

    // MARK: - Variables

    private var mounted: [String: Mounted] = [:]
    private var dirty: Set<String> = []
    /// Bodies evaluated again, and bodies evaluated for the first time, by kind.
    private(set) var evaluations: [ReadModelSpikeBody: Int] = [:]
    private(set) var mounts: [ReadModelSpikeBody: Int] = [:]

    // MARK: - Initializers

    init(root: Node) {
        mounted["root"] = Mounted(node: root, input: AnyEquatable("root"), depth: 0)
        evaluate("root", isMount: true)
        reset()
    }

    // MARK: - Actions - Evaluation

    /// Evaluates every body a change invalidated, parents first.
    func settle() {
        while let key = dirty.min(by: { (mounted[$0]?.depth ?? 0) < (mounted[$1]?.depth ?? 0) }) {
            dirty.remove(key)
            if mounted[key] != nil { evaluate(key, isMount: false) }
        }
    }

    func reset() {
        evaluations = [:]
        mounts = [:]
    }

    private func evaluate(_ key: String, isMount: Bool) {
        guard let view = mounted[key] else { return }
        dirty.remove(key)
        if let kind = view.node.kind {
            if isMount { mounts[kind, default: 0] += 1 } else { evaluations[kind, default: 0] += 1 }
        }
        view.generation += 1
        let generation = view.generation
        var children: [Child] = []
        withObservationTracking {
            children = view.node.read()
        } onChange: { [weak self] in
            MainActor.assumeIsolated { self?.invalidate(key, generation: generation) }
        }
        let keys = Set(children.map(\.key))
        for gone in view.children where !keys.contains(gone) { unmount(gone) }
        view.children = children.map(\.key)
        for child in children {
            if let existing = mounted[child.key] {
                guard existing.input != child.input else { continue }
                existing.input = child.input
                existing.node = child.node
                evaluate(child.key, isMount: false)
            } else {
                mounted[child.key] = Mounted(node: child.node, input: child.input, depth: view.depth + 1)
                evaluate(child.key, isMount: true)
            }
        }
    }

    /// A body's earlier reads no longer count once it has evaluated again.
    private func invalidate(_ key: String, generation: Int) {
        guard mounted[key]?.generation == generation else { return }
        dirty.insert(key)
    }

    private func unmount(_ key: String) {
        guard let view = mounted.removeValue(forKey: key) else { return }
        dirty.remove(key)
        for child in view.children { unmount(child) }
    }
}

/// A value compared through its own `Equatable` conformance.
struct AnyEquatable: Equatable {
    private let value: any Equatable

    init(_ value: some Equatable) {
        self.value = value
    }

    static func == (lhs: AnyEquatable, rhs: AnyEquatable) -> Bool {
        lhs.value.isEqual(to: rhs.value)
    }
}

extension Equatable {
    fileprivate func isEqual(to other: any Equatable) -> Bool {
        (other as? Self) == self
    }
}

// MARK: - Mirror

extension SidebarBodies {
    /// The views `ReadModelSpikeSidebar` draws over the bench's Space, each
    /// reading what its body reads.
    convenience init(mirroring bench: ReadModelSpikeBench) {
        let (workspace, space, window, outline, state) = (
            bench.workspace, bench.space, bench.window, bench.outline, bench.core.state
        )
        self.init(
            root: Node(kind: nil) {
                [
                    Child(
                        key: "switcher", input: AnyEquatable("switcher"),
                        node: Node(kind: .switcher) {
                            ReadModelSpikeSwitcher.segments(workspace: workspace, shownSpaceID: space.id).map {
                                segment in
                                Child(
                                    key: "segment-\(segment.id)", input: AnyEquatable(segment),
                                    node: Node(kind: .segment) {
                                        _ = ReadModelSpikeSwitcherSegment.Shown(settings: segment.settings)
                                        return []
                                    })
                            }
                        }),
                    Child(
                        key: "header", input: AnyEquatable("header"),
                        node: Node(kind: .header) {
                            _ = ReadModelSpikeHeader.Shown(settings: space.settings)
                            return []
                        }),
                    Child(
                        key: "list", input: AnyEquatable("list"),
                        node: Node(kind: .list) {
                            ReadModelSpikeList.items(space: space, window: window, outline: outline, state: state).map {
                                Child(key: $0.id, input: AnyEquatable($0), node: Self.node(for: $0, state: state))
                            }
                        }),
                ]
            })
    }

    private static func node(for item: ReadModelSpikeList.Item, state: CoreState) -> Node {
        switch item.content {
        case .header:
            Node(kind: .sectionHeader) { [] }
        case .tab(let tab, let page):
            Node(kind: .row) {
                _ = ReadModelSpikeTabRow.Shown(tab: tab, page: page, favicons: state.favicons)
                return []
            }
        case .folder(let folder):
            Node(kind: .row) {
                _ = ReadModelSpikeFolderRow.Shown(folder: folder)
                return []
            }
        case .split(let members):
            Node(kind: .row) {
                _ = ReadModelSpikeSplitRow.Shown(members: members, favicons: state.favicons)
                return []
            }
        }
    }

    /// Runs `edit` `runs` times on `bench`, each after its preparation, and
    /// counts the bodies each run evaluated.
    func measure(_ edit: ReadModelSpikeEdit, on bench: ReadModelSpikeBench, runs: Int) -> SidebarMeasurement {
        var measurement = SidebarMeasurement(name: edit.name)
        for run in 0..<runs {
            edit.prepare?(bench, run)
            settle()
            reset()
            bench.clearChanges()
            let start = ContinuousClock.now
            edit.perform(bench, run)
            let applied = start.duration(to: .now)
            settle()
            measurement.record(
                evaluations: evaluations, mounts: mounts, applied: applied, changes: bench.changeKinds)
        }
        return measurement
    }
}

/// What one edit's runs evaluated.
struct SidebarMeasurement {
    let name: String
    private(set) var evaluations: [[ReadModelSpikeBody: Int]] = []
    private(set) var mounts: [[ReadModelSpikeBody: Int]] = []
    private(set) var applied: [Duration] = []
    private(set) var changes: Set<String> = []

    init(name: String) {
        self.name = name
    }

    /// Whether the runs changed anything the core reports.
    var changed: Bool { !changes.isEmpty }

    mutating func record(
        evaluations: [ReadModelSpikeBody: Int], mounts: [ReadModelSpikeBody: Int], applied: Duration,
        changes: Set<String>
    ) {
        self.evaluations.append(evaluations)
        self.mounts.append(mounts)
        self.applied.append(applied)
        self.changes.formUnion(changes)
    }

    func maximum(_ kind: ReadModelSpikeBody) -> Int { evaluations.map { $0[kind] ?? 0 }.max() ?? 0 }

    func mean(_ kind: ReadModelSpikeBody) -> Double {
        evaluations.isEmpty ? 0 : Double(evaluations.map { $0[kind] ?? 0 }.reduce(0, +)) / Double(evaluations.count)
    }

    func maximumMounts(_ kind: ReadModelSpikeBody) -> Int { mounts.map { $0[kind] ?? 0 }.max() ?? 0 }
}
