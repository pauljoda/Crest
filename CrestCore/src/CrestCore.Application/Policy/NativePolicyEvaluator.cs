using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Bounded, deterministic domain calls for existing synchronous native APIs.
/// This path owns no session, queue, engine, I/O, callback, or retained state.
public static partial class NativePolicyEvaluator {
    #region Variables

    public const int MaximumInputBytes = 16_384;
    public const int MaximumOutputBytes = 65_536;

    #endregion

    #region Actions - Policy

    public static byte[] Evaluate(ReadOnlySpan<byte> utf8) {
        if (utf8.Length > MaximumInputBytes) throw new ProtocolException(ProtocolErrorCodes.PolicyInputLimit);
        var request = Protocol.Parse(utf8);
        if (request.GetProperty("version").GetInt32() != 1) throw new ProtocolException(ProtocolErrorCodes.VersionMismatch);
        var operation = PolicyOperationCodes.Parse(Protocol.Text(request, "operation"));
        if (EvaluateDownloads(operation, request) is { } download) return Encode(download);
        if (EvaluateCredentials(operation, request) is { } credential) return Encode(credential);
        if (EvaluateSearch(operation, request) is { } search) return Encode(search);
        if (EvaluateTranslation(operation, request) is { } translation) return Encode(translation);
        if (EvaluateSitePermissions(operation, request) is { } sitePermission) return Encode(sitePermission);
        if (EvaluateOrigins(operation, request) is { } origin) return Encode(origin);
        if (EvaluateAuthentication(operation, request) is { } authentication) return Encode(authentication);
        if (EvaluateLinks(operation, request) is { } links) return Encode(links);
        if (EvaluateQuickWindow(operation, request) is { } quickWindow) return Encode(quickWindow);
        if (EvaluatePresentation(operation, request) is { } presentation) return Encode(presentation);
        if (EvaluateWorkspace(operation, request) is { } workspace) return Encode(workspace);
        if (EvaluateWindows(operation, request) is { } window) return Encode(window);
        if (EvaluateSetup(operation, request) is { } setup) return Encode(setup);
        if (EvaluateShortcuts(operation, request) is { } shortcut) return Encode(shortcut);
        if (EvaluateLaunch(operation, request) is { } launch) return Encode(launch);
        if (EvaluateMedia(operation, request) is { } media) return Encode(media);
        if (operation is PolicyOperation.NavigationLink or PolicyOperation.NavigationModifiedLink) {
            bool peek, newTab;
            if (operation == PolicyOperation.NavigationModifiedLink) {
                Protocol.Members(request, "version", "operation", "url", "userActivatedLink", "topLevel",
                    "commandModified", "optionModified", "middleClick", "peekModifier", "shiftModified", "focusesNewTabs",
                    "hasContext", "placement", "savedUrl", "automaticallyOpensPeek");
                var preference = Protocol.Text(request, "peekModifier") switch {
                    "option" => LinkPeekModifier.Option,
                    "command" => LinkPeekModifier.Command,
                    _ => throw new ProtocolException(ProtocolErrorCodes.InvalidPeekModifier)
                };
                (peek, newTab) = LinkNavigationPolicy.Modifiers(request.GetProperty("commandModified").GetBoolean(),
                    request.GetProperty("optionModified").GetBoolean(), request.GetProperty("middleClick").GetBoolean(), preference);
            } else {
                Protocol.Members(request, "version", "operation", "url", "userActivatedLink", "topLevel",
                    "peekModified", "newTabModified", "shiftModified", "focusesNewTabs", "hasContext",
                    "placement", "savedUrl", "automaticallyOpensPeek");
                peek = request.GetProperty("peekModified").GetBoolean();
                newTab = request.GetProperty("newTabModified").GetBoolean();
            }
            var decision = LinkNavigationPolicy.Decide(request.GetProperty("url").GetString(),
                request.GetProperty("userActivatedLink").GetBoolean(), request.GetProperty("topLevel").GetBoolean(),
                peek, newTab,
                request.GetProperty("shiftModified").GetBoolean(), request.GetProperty("focusesNewTabs").GetBoolean(),
                request.GetProperty("hasContext").GetBoolean(), TabPlacementCodes.Parse(request.GetProperty("placement").GetString()),
                request.GetProperty("savedUrl").GetString(), request.GetProperty("automaticallyOpensPeek").GetBoolean());
            return Encode(new() {
                ["decision"] = decision switch {
                    LinkNavigationDecision.PeekModifier => "peekModifier",
                    LinkNavigationDecision.PeekSavedSite => "peekSavedSite",
                    LinkNavigationDecision.BackgroundTab => "backgroundTab",
                    LinkNavigationDecision.ForegroundTab => "foregroundTab",
                    _ => "navigate"
                }
            });
        }
        if (operation == PolicyOperation.Limits) {
            // One answer for every capacity the core enforces, so native
            // surfaces never keep their own copies of the numbers.
            Protocol.Members(request, "version", "operation");
            return Encode(new() {
                ["pinnedTabs"] = BrowserLimits.PinnedTabs,
                ["folders"] = BrowserLimits.Folders,
                ["folderDepth"] = BrowserLimits.FolderDepth,
                ["historyEntries"] = BrowserLimits.HistoryEntries,
                ["splitMembers"] = BrowserLimits.SplitMembers,
                ["brandColors"] = BrowserLimits.BrandColors,
                ["crestPalette"] = BrowserLimits.CrestPalette,
                ["spaces"] = BrowserLimits.Spaces,
                ["tabsPerSpace"] = BrowserLimits.TabsPerSpace,
                ["syncRecords"] = NativeSyncJournal.MaximumRecords
            });
        }
        if (operation == PolicyOperation.HistoryNormalize) {
            Protocol.Members(request, "version", "operation", "url");
            return Encode(new() { ["url"] = HistoryPolicy.Normalize(Protocol.Text(request, "url")) });
        }
        if (operation == PolicyOperation.ResidencyReleaseLimit) {
            Protocol.Members(request, "version", "operation", "level", "platform", "eligiblePageCount");
            return Encode(new() {
                ["limit"] = PageResidencyPolicy.ReleaseLimit(Level(request),
                request.GetProperty("eligiblePageCount").GetInt32(), Platform(request))
            });
        }
        if (operation == PolicyOperation.ResidencyReleasePlan) {
            Protocol.Members(request, "version", "operation", "level", "platform", "focusedIndex", "candidates");
            var candidates = new List<ResidencyCandidate>();
            foreach (var value in request.GetProperty("candidates").EnumerateArray()) {
                Protocol.Members(value, "tabID", "inactiveSince", "keepsPageLoaded", "isPresented", "presentedIndex");
                candidates.Add(new(Protocol.Id(value, "tabID").ToString(),
                    Optional(value, "inactiveSince") is { } stamp ? stamp.GetDouble() : null,
                    Optional(value, "keepsPageLoaded")?.GetBoolean() ?? false,
                    Optional(value, "isPresented")?.GetBoolean() ?? false,
                    Optional(value, "presentedIndex") is { } index ? index.GetInt32() : null));
                if (candidates.Count > PageResidencyPolicy.MaximumCandidates)
                    throw new ProtocolException(ProtocolErrorCodes.ResidencyCandidateLimit);
            }
            var plan = PageResidencyPolicy.ReleasePlan(candidates, Level(request), Platform(request),
                Optional(request, "focusedIndex") is { } focus ? focus.GetInt32() : null);
            return Encode(new() { ["tabIDs"] = Identifiers(plan.OffScreen), ["fallbackTabIDs"] = Identifiers(plan.PresentedFallback) });
        }
        if (operation == PolicyOperation.ResidencyProcessRecovery) {
            Protocol.Members(request, "version", "operation", "consecutiveTerminations");
            var action = PageProcessRecoveryPolicy.Decide(request.GetProperty("consecutiveTerminations").GetInt32());
            return Encode(new() {
                ["action"] = action == ProcessRecoveryAction.Reload ? "reload" : "showFailure",
                ["maximumAutomaticReloads"] = PageProcessRecoveryPolicy.MaximumAutomaticReloads
            });
        }
        if (operation == PolicyOperation.TabsDismissal) {
            Protocol.Members(request, "version", "operation", "placement", "isStartPage", "tabCount");
            var placement = Optional(request, "placement") is null ? (TabPlacement?)null
                : (TabPlacementCodes.Parse(Protocol.Text(request, "placement")) ?? throw new ProtocolException(ProtocolErrorCodes.InvalidPlacement));
            var action = TabDismissalPolicy.Decide(placement,
                Optional(request, "isStartPage")?.GetBoolean() ?? false,
                request.GetProperty("tabCount").GetInt32());
            return Encode(new() {
                ["action"] = action switch {
                    TabDismissalAction.UnloadPage => "unloadPage",
                    TabDismissalAction.CloseTab => "closeTab",
                    _ => "closeWindow"
                }
            });
        }
        throw new ProtocolException(ProtocolErrorCodes.UnknownPolicy);
    }

    private static byte[] Encode(JsonObject value) => Encoding.UTF8.GetBytes(value.ToJsonString());

    private static JsonElement? Optional(JsonElement value, string field) =>
        value.TryGetProperty(field, out var member) && member.ValueKind != JsonValueKind.Null ? member : null;

    private static JsonArray Identifiers(IReadOnlyList<string> values) =>
        new(values.Select(value => (JsonNode?)JsonValue.Create(value)).ToArray());

    private static MemoryPressureLevel Level(JsonElement request) => Protocol.Text(request, "level") switch {
        "warning" => MemoryPressureLevel.Warning,
        "critical" => MemoryPressureLevel.Critical,
        _ => throw new ProtocolException(ProtocolErrorCodes.InvalidPressureLevel)
    };

    private static MemoryPressurePlatform Platform(JsonElement request) => Protocol.Text(request, "platform") switch {
        "desktop" => MemoryPressurePlatform.Desktop,
        "mobile" => MemoryPressurePlatform.Mobile,
        _ => throw new ProtocolException(ProtocolErrorCodes.InvalidPressurePlatform)
    };

    #endregion
}
