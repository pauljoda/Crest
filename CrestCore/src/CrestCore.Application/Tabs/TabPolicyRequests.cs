using System.Text.Json;

using CrestCore.Contracts;
using CrestCore.Domain;

using static CrestCore.Application.PolicyFields;

namespace CrestCore.Application;

/// Typed requests for the page-residency, process-recovery and tab-dismissal
/// policy operations.
internal static class TabPolicyRequests {
    #region Actions - Decoding

    public sealed record ReleaseLimit(MemoryPressureLevel Level, int EligiblePageCount, DevicePlatform Platform) {
        public static ReleaseLimit Decode(JsonElement request) {
            Members(request, "level", "platform", "eligiblePageCount");
            var level = PressureLevel(request);
            int count = Integer(request, "eligiblePageCount");
            return new(level, count, DeviceCodes.Platform(request));
        }
    }

    public sealed record ReleasePlan(IReadOnlyList<ResidencyCandidate> Candidates, MemoryPressureLevel Level,
        DevicePlatform Platform, int? FocusedIndex) {
        public static ReleasePlan Decode(JsonElement request) {
            Members(request, "level", "platform", "focusedIndex", "candidates");
            var candidates = new List<ResidencyCandidate>();
            foreach (var value in Element(request, "candidates").EnumerateArray()) {
                Protocol.Members(value, "tabID", "inactiveSince", "keepsPageLoaded", "isPresented", "presentedIndex");
                candidates.Add(new(Protocol.Id(value, "tabID").ToString(), OptionalNumber(value, "inactiveSince"),
                    OptionalFlag(value, "keepsPageLoaded") ?? false, OptionalFlag(value, "isPresented") ?? false,
                    OptionalInteger(value, "presentedIndex")));
                if (candidates.Count > PageResidencyPolicy.MaximumCandidates)
                    throw new ProtocolException(ProtocolErrorCodes.ResidencyCandidateLimit);
            }
            var level = PressureLevel(request);
            var platform = DeviceCodes.Platform(request);
            return new(candidates, level, platform, OptionalInteger(request, "focusedIndex"));
        }
    }

    public sealed record ProcessRecovery(int ConsecutiveTerminations) {
        public static ProcessRecovery Decode(JsonElement request) {
            Members(request, "consecutiveTerminations");
            return new(Integer(request, "consecutiveTerminations"));
        }
    }

    private static MemoryPressureLevel PressureLevel(JsonElement request) =>
        MemoryPressureLevel.Named(Protocol.Text(request, "level")) ?? throw new ProtocolException(ProtocolErrorCodes.InvalidPressureLevel);

    #endregion
}
