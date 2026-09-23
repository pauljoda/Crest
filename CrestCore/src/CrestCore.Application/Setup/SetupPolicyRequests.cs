using System.Text.Json;

using CrestCore.Contracts;
using CrestCore.Domain;

using static CrestCore.Application.PolicyFields;

namespace CrestCore.Application;

/// Typed requests for the manual-setup and onboarding policy operations. The
/// draft itself stays native; these carry the edit or finish being judged.
internal static class SetupPolicyRequests {
    #region Variables

    private const int MaximumSetupUrlLength = 8_192;
    private const int MaximumSetupTitleLength = 4_096;

    #endregion

    #region Actions - Decoding

    public sealed record Space(int DraftCount) {
        public static Space Decode(JsonElement request) {
            Members(request, "draftCount");
            return new(Integer(request, "draftCount"));
        }
    }

    public sealed record Tab(TabPlacement Placement, int ExistingPinnedCount, int AddedPinnedCount, string Url, string? Title) {
        public static Tab Decode(JsonElement request) {
            Members(request, "placement", "existingPinnedCount", "addedPinnedCount", "url", "title");
            var placement = TabPlacementCodes.Parse(Protocol.Text(request, "placement", 16))
                ?? throw new ProtocolException(ProtocolErrorCodes.InvalidPlacement);
            int existing = Integer(request, "existingPinnedCount"), added = Integer(request, "addedPinnedCount");
            var url = Protocol.Text(request, "url", MaximumSetupUrlLength);
            return new(placement, existing, added, url, Protocol.OptionalText(request, "title", MaximumSetupTitleLength));
        }
    }

    public sealed record Reconcile(IReadOnlyList<ManualSetupDraft> Drafts, IReadOnlyList<Guid> Existing) {
        public static Reconcile Decode(JsonElement request) {
            Members(request, "drafts", "existing");
            var drafts = new List<ManualSetupDraft>();
            foreach (var item in Element(request, "drafts").EnumerateArray()) {
                if (drafts.Count >= ManualSetupPolicy.MaximumDrafts) throw new BrowserRuleException(BrowserRuleCodes.SpaceLimitReached);
                Protocol.Members(item, "id", "isNew");
                drafts.Add(new(Protocol.Id(item, "id"), Flag(item, "isNew")));
            }
            var existing = new List<Guid>();
            foreach (var item in Element(request, "existing").EnumerateArray()) {
                if (existing.Count >= ManualSetupPolicy.MaximumDrafts) throw new BrowserRuleException(BrowserRuleCodes.SpaceLimitReached);
                existing.Add(Protocol.Id(item));
            }
            return new(drafts, existing);
        }
    }

    public sealed record Completion(OnboardingEntryPoint EntryPoint, bool HasCompletedSetup, bool IsPrivateBrowsing) {
        public static Completion Decode(JsonElement request) {
            Members(request, "entryPoint", "hasCompletedSetup", "isPrivateBrowsing");
            var entryPoint = SetupCodes.EntryPoint(Protocol.Text(request, "entryPoint", 32));
            bool completed = Flag(request, "hasCompletedSetup");
            return new(entryPoint, completed, Flag(request, "isPrivateBrowsing"));
        }
    }

    public sealed record Guide(OnboardingGuideFacts Facts) {
        public static Guide Decode(JsonElement request) {
            Members(request, "target", "originalFirst", "currentFirst", "originalTarget", "currentTarget", "previewFirst",
                "hasManualPlan", "locked");
            var target = SetupCodes.Identity(request, "target") ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
            return new(new OnboardingGuideFacts(target, SetupCodes.Identity(request, "originalFirst"), SetupCodes.Identity(request, "currentFirst"),
                SetupCodes.Identity(request, "originalTarget"), SetupCodes.Identity(request, "currentTarget"),
                SetupCodes.Identity(request, "previewFirst"), Flag(request, "hasManualPlan"), Flag(request, "locked")));
        }
    }

    #endregion
}
