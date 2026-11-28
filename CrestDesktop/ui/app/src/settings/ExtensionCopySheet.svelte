<script lang="ts">
  import { EngineKind, ExtensionCopyDestinations, type InstalledExtension, type SpaceState } from "@crest/contracts";
  import { untrack } from "svelte";

  import type { Session } from "../boot";
  import { extensions } from "../extensions";
  import { Sheet } from "../shell/prompts/PromptSheet";

  /** BrowserExtensionCopySheet: the other Spaces a copy of a Web Store extension may go to, each chosen or not. */
  let { session, space, spaces, item, onDone }: {
    session: Session;
    space: SpaceState;
    spaces: readonly SpaceState[];
    item: InstalledExtension;
    onDone: () => void;
  } = $props();

  let destinations = $state.raw<readonly string[] | null>(null);
  // A query the core couldn't answer, which the sheet says and offers again, apart from a Space list that is empty.
  let failed = $state(false);
  let chosen = $state.raw<readonly string[]>([]);
  const find = (spaceId: string, extensionId: string) => {
    failed = false;
    void session.core.query(ExtensionCopyDestinations({ spaceId, engine: EngineKind.chromium, extensionId }))
      .then((answer) => {
        destinations = answer.spaceIds;
      }, () => {
        failed = true;
      });
  };
  $effect(() => {
    const spaceId = space.id;
    const extensionId = item.id;
    untrack(() => find(spaceId, extensionId));
  });
</script>

<Sheet title={`Install ${item.name} in Other Spaces`} primary="Install" secondary="Cancel"
  onPrimary={() => {
    onDone();
    const [first, ...rest] = chosen;
    if (first) void extensions.install(session, item.id, first, rest);
  }}
  onEscape={onDone}>
  <div class="extension-spaces" role="group" aria-label="Spaces">
    {#if failed}
      <p class="sheet-message">Crest couldn’t find the other Spaces.</p>
      <button type="button" class="sheet-button" onclick={() => find(space.id, item.id)}>Try Again</button>
    {:else if destinations === null}
      <p class="sheet-message">Finding Spaces…</p>
    {:else if destinations.length === 0}
      <p class="sheet-message">Every Space that can run it has it already.</p>
    {:else}
      {#each destinations as spaceId (spaceId)}
        {@const checked = chosen.includes(spaceId)}
        <label class="extension-space">
          <input type="checkbox" {checked}
            onchange={() => (chosen = checked ? chosen.filter((id) => id !== spaceId) : [...chosen, spaceId])} />{spaces.find((candidate) => candidate.id === spaceId)?.settings.name ?? "Space"}
        </label>
      {/each}
    {/if}
  </div>
</Sheet>
