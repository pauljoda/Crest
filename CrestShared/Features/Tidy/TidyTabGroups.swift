import Foundation

/// Groups tabs by their meaning vectors, with no model call: the vectors are
/// centered on their mean, merged by average linkage over cosine distance, and
/// cut at whichever height from 0.60 to 1.00 gives the best silhouette. Only
/// groups of two or more tabs are kept.
struct TidyTabGroups {
    // MARK: - Static Variables

    private static let cutHeights: [Float] = stride(from: 0, through: 8, by: 1).map { 0.6 + Float($0) * 0.05 }

    // MARK: - Variables

    /// Each tab's cosine distance to every other, after centering.
    private let distances: [[Float]]

    // MARK: - Initializers

    init(vectors: [[Float]]) {
        guard let dimension = vectors.first?.count else {
            distances = []
            return
        }
        var mean = [Float](repeating: 0, count: dimension)
        for vector in vectors {
            for index in 0..<dimension { mean[index] += vector[index] / Float(vectors.count) }
        }
        let centered = vectors.map { vector in
            TidyTabEmbedder.unitLength((0..<dimension).map { vector[$0] - mean[$0] })
        }
        distances = centered.map { first in
            centered.map { second in
                min(max(1 - zip(first, second).reduce(0) { $0 + $1.0 * $1.1 }, 0), 2)
            }
        }
    }

    // MARK: - Actions - Grouping

    /// The groups of two or more tabs, as indices into the vectors, each with
    /// its most typical tab first: the one closest on average to the rest.
    func groups() -> [[Int]] {
        guard distances.count >= 2 else { return [] }
        let merges = averageLinkageMerges()
        var best: (silhouette: Float, clusters: [[Int]])?
        for height in Self.cutHeights {
            let clusters = clusters(from: merges, cutAt: height)
            let score = silhouette(of: clusters)
            if best == nil || score > best!.silhouette { best = (score, clusters) }
        }
        return best!.clusters.filter { $0.count >= 2 }.map { members in
            let spread = members.map { tab in members.reduce(0) { $0 + distances[tab][$1] } }
            return members.indices.sorted { spread[$0] < spread[$1] }.map { members[$0] }
        }
    }

    /// Every merge, in order, with the height it happened at.
    private func averageLinkageMerges() -> [(kept: Int, absorbed: Int, height: Float)] {
        var linkage = distances
        var sizes = [Int](repeating: 1, count: distances.count)
        var active = Set(distances.indices)
        var merges: [(kept: Int, absorbed: Int, height: Float)] = []
        while active.count > 1 {
            var closest = (kept: 0, absorbed: 0, height: Float.infinity)
            let ordered = active.sorted()
            for (position, first) in ordered.enumerated() {
                for second in ordered[(position + 1)...] where linkage[first][second] < closest.height {
                    closest = (first, second, linkage[first][second])
                }
            }
            for other in active where other != closest.kept && other != closest.absorbed {
                linkage[closest.kept][other] =
                    (Float(sizes[closest.kept]) * linkage[closest.kept][other]
                        + Float(sizes[closest.absorbed]) * linkage[closest.absorbed][other])
                    / Float(sizes[closest.kept] + sizes[closest.absorbed])
                linkage[other][closest.kept] = linkage[closest.kept][other]
            }
            sizes[closest.kept] += sizes[closest.absorbed]
            active.remove(closest.absorbed)
            merges.append(closest)
        }
        return merges
    }

    private func clusters(from merges: [(kept: Int, absorbed: Int, height: Float)], cutAt height: Float) -> [[Int]] {
        var parents = Array(distances.indices)
        func root(of index: Int) -> Int {
            var index = index
            while parents[index] != index { index = parents[index] }
            return index
        }
        for merge in merges where merge.height <= height {
            parents[root(of: merge.absorbed)] = root(of: merge.kept)
        }
        return Dictionary(grouping: distances.indices, by: root(of:)).values.map { $0.sorted() }
            .sorted { $0[0] < $1[0] }
    }

    /// The mean silhouette, or -1 when everything is one cluster.
    private func silhouette(of clusters: [[Int]]) -> Float {
        guard clusters.count >= 2 else { return -1 }
        var clusterOfTab = [Int](repeating: 0, count: distances.count)
        for (cluster, members) in clusters.enumerated() {
            for member in members { clusterOfTab[member] = cluster }
        }
        var total: Float = 0
        for tab in distances.indices {
            let companions = clusters[clusterOfTab[tab]].filter { $0 != tab }
            guard !companions.isEmpty else { continue }
            let cohesion = companions.reduce(0) { $0 + distances[tab][$1] } / Float(companions.count)
            var separation = Float.infinity
            for (cluster, members) in clusters.enumerated() where cluster != clusterOfTab[tab] {
                separation = min(separation, members.reduce(0) { $0 + distances[tab][$1] } / Float(members.count))
            }
            let spread = max(cohesion, separation)
            if spread > 0 { total += (separation - cohesion) / spread }
        }
        return total / Float(distances.count)
    }
}
