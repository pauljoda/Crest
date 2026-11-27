<script lang="ts">
  import { RenameTab, type TabState } from "@crest/contracts";
  import { untrack } from "svelte";

  import type { Session } from "../boot";
  import { Sheet } from "./prompts/PromptSheet";
  import { send } from "./sidebar-menus";

  /** A pinned tile has no room for a field, so its rename asks in a dialog, as the Mac's does. */
  let { session, spaceId, tab, onDone }: {
    session: Session; spaceId: string; tab: TabState; onDone: () => void;
  } = $props();

  let title = $state(untrack(() => tab.displayTitle));
</script>

<Sheet title="Rename Tab" primary="Rename" secondary="Cancel"
  onPrimary={() => {
    void send(session, RenameTab({ workspaceId: session.workspaceId, spaceId, tabId: tab.id, title }));
    onDone();
  }}
  onEscape={onDone}>
  <input class="sheet-field" placeholder="Tab Name" aria-label="Tab Name" bind:value={title}
    onfocusin={(event) => event.currentTarget.select()} data-autofocus="true" />
</Sheet>
