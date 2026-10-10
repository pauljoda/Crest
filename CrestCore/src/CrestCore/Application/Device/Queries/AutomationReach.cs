using CrestCore.Application;

namespace CrestCore.Contracts;

/// What local tools may reach now: nothing while automation is off, and
/// otherwise each Space the person allowed that their own session holds and is
/// not being deleted, in the session's order, with whether it is locked. A
/// private window's Spaces and a borrowed workspace's are never reached.
public sealed record AutomationReach : Query<AutomationReachList> {
    #region Actions - Answering

    internal override AutomationReachList Answer(CrestApp app) => app.Device.AutomationReach();

    #endregion
}
