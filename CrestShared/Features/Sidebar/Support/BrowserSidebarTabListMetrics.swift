import CoreGraphics

/// The geometry the sidebar's tab list draws its own furniture with — the seam
/// between the saved run and the current one, and the band a run keeps at its
/// end — resolved once per shell rather than spelled out by each section.
///
/// The rows themselves are sized by `BrowserSidebarTabRowMetrics`. What lives
/// here is everything between them: the divider, the control it makes room for,
/// and the landing band an empty run needs so a drop has somewhere to aim.
struct BrowserSidebarTabListMetrics: Equatable, Sendable {
    /// How far the seam between the two runs sits from the list's edges.
    let dividerHorizontalInset: CGFloat

    /// How much air the seam keeps above and below itself.
    let dividerVerticalInset: CGFloat

    /// How much of the divider's trailing end is given up while the clear
    /// control is showing, so the line stops short of it rather than running
    /// underneath.
    let clearActionOcclusionWidth: CGFloat

    /// Whether the seam carries the clear-current-tabs control at all.
    ///
    /// The control waits for a pointer to arrive over the list before it
    /// appears, which is a reveal a finger cannot ask for. Where it can never
    /// be revealed the seam is a plain divider, and clearing lives in the Space
    /// header's menu instead.
    let carriesClearAction: Bool

    /// The height of the band a run keeps for the drop it cannot otherwise
    /// show.
    ///
    /// An empty run — a cleared current list, an unfiled saved run under a
    /// folder that holds every saved tab, a pinned grid nobody has filled — has
    /// no row to anchor an insertion line on and no region to aim at. The band
    /// stands in for that first row. A touch shell keeps it at every run's end
    /// rather than only when the run is empty, because a finger cannot aim at
    /// the seam between two rows that touch.
    let sectionEndBandHeight: CGFloat

    /// A pointer shell: a tight seam that carries the clear control, and a band
    /// only wide enough to hold an insertion line.
    static let pointer = BrowserSidebarTabListMetrics(
        dividerHorizontalInset: 12,
        dividerVerticalInset: 3,
        clearActionOcclusionWidth: 52,
        carriesClearAction: true,
        sectionEndBandHeight: CrestSpacing.medium
    )

    /// A touch shell: a plain seam with more air around it, and a band a finger
    /// can land in.
    static let touch = BrowserSidebarTabListMetrics(
        dividerHorizontalInset: 16,
        dividerVerticalInset: 5,
        clearActionOcclusionWidth: 0,
        carriesClearAction: false,
        sectionEndBandHeight: 28
    )
}
