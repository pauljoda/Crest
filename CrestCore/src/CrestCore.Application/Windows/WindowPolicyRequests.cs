using System.Text.Json;

using CrestCore.Contracts;
using CrestCore.Domain;

using static CrestCore.Application.PolicyFields;

namespace CrestCore.Application;

/// Typed requests for the window policy operations. Window state is
/// device-local, so these carry identities and presence facts only.
internal static class WindowPolicyRequests {
    #region Actions - Decoding

    public sealed record Repair(Guid SelectedSpaceId, bool CapturesSelection, IReadOnlyList<WindowSpaceFacts> Spaces,
        IReadOnlyList<WindowSplitLayout> Layouts) {
        public static Repair Decode(JsonElement request) {
            Members(request, "selectedSpaceID", "capturesSelection", "spaces", "splitLayouts");
            var spaces = new List<WindowSpaceFacts>();
            foreach (var item in Element(request, "spaces").EnumerateArray()) {
                if (spaces.Count >= WindowStatePolicy.MaximumSpaces) throw new BrowserRuleException(BrowserRuleCodes.WindowStateLimit);
                Protocol.Members(item, "id", "windowTab", "captured", "hasTabs");
                spaces.Add(new(Protocol.Id(item, "id"), Flag(item, "windowTab"), Flag(item, "captured"), Flag(item, "hasTabs")));
            }
            var layouts = new List<WindowSplitLayout>();
            foreach (var item in Element(request, "splitLayouts").EnumerateArray()) {
                if (layouts.Count >= WindowStatePolicy.MaximumSplitLayouts) throw new BrowserRuleException(BrowserRuleCodes.WindowStateLimit);
                Protocol.Members(item, "groupID", "columns", "liveMembers");
                layouts.Add(new(Protocol.Id(item, "groupID"), Integer(item, "columns"), OptionalInteger(item, "liveMembers")));
            }
            var selected = Protocol.Id(request, "selectedSpaceID");
            return new(selected, Flag(request, "capturesSelection"), spaces, layouts);
        }
    }

    /// Only the entries a group could hold, plus one to detect an overlong list,
    /// are read; the policy refuses any list longer than a group.
    public sealed record SplitLayout(IReadOnlyList<double> Fractions) {
        public static SplitLayout Decode(JsonElement request) {
            Members(request, "fractions");
            return new(Element(request, "fractions").EnumerateArray().Take(BrowserTabCollection.MaximumSplitMembers + 1)
                .Select(value => value.GetDouble()).ToArray());
        }
    }

    public sealed record TearOff(bool SpaceMatches, bool SpaceLocked, bool ContainsTab, int? SelectionCount,
        bool SelectionIncludesTab) {
        public static TearOff Decode(JsonElement request) {
            Members(request, "spaceMatches", "spaceLocked", "containsTab", "selectionCount", "selectionIncludesTab");
            int? count = OptionalInteger(request, "selectionCount");
            if (count < 0) throw new ProtocolException(ProtocolErrorCodes.InvalidLimit);
            bool matches = Flag(request, "spaceMatches"), locked = Flag(request, "spaceLocked"),
                containsTab = Flag(request, "containsTab");
            return new(matches, locked, containsTab, count, Flag(request, "selectionIncludesTab"));
        }
    }

    #endregion
}
