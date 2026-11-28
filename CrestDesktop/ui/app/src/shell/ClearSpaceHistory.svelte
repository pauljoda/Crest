<script lang="ts">
  import { BrowsingDataRange, ClearHistory } from "@crest/contracts";
  import { untrack } from "svelte";

  import type { Session } from "../boot";
  import { coreState } from "../use-core";
  import { Sheet } from "./prompts/PromptSheet";
  import { send } from "./sidebar-menus";

  /**
   * Clearing a Space's history can't be undone, so the person confirms, told
   * what it reaches: the group's shared history, or the Space's alone, as the
   * Mac's BrowserSidebarClearHistoryDialog asks. The question goes with the
   * Space it was asked about.
   */
  let { session, spaceId, onDone }: { session: Session; spaceId: string; onDone: () => void } = $props();

  const asked = $derived.by(() => {
    const state = coreState(session);
    const workspace = state.workspaces.get(session.workspaceId);
    const space = workspace?.spaces.get(spaceId);
    const shown = state.windows.get(session.windowId)?.shownSpaceId === spaceId;
    if (!workspace || !space) return { space: null, shown };
    const primaryId = space.membership?.primaryId ?? space.id;
    const members = [...workspace.spaces.values()].filter((candidate) => candidate.id === primaryId || candidate.membership?.primaryId === primaryId);
    const primary = workspace.spaces.get(primaryId) ?? space;
    return { space, shown, members: members.length, primaryName: primary.settings.name };
  });
  $effect(() => {
    if (!asked.space || !asked.shown) untrack(onDone);
  });
</script>

{#if asked.space}
  <Sheet title={`Clear history for ${asked.space.settings.name}?`} primary="Clear History" secondary="Cancel" warning destructive
    onPrimary={() => {
      void send(session, ClearHistory({ workspaceId: session.workspaceId, spaceId, range: BrowsingDataRange.allTime }));
      onDone();
    }}
    onEscape={onDone}>
    <p class="sheet-message">
      {(asked.members ?? 0) > 1 ? `This clears the history ${asked.primaryName} and its Sub-Spaces share.` : "History in other Spaces is not affected."}
    </p>
  </Sheet>
{/if}
