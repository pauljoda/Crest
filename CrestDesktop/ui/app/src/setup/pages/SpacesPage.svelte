<script lang="ts">
  import { AddSetupSpace, MoveSetupSpace, RemoveSetupSpace, type SetupDraftSpace } from "@crest/contracts";

  import type { Session } from "../../boot";
  import { type MenuEntry, showContextMenu } from "../../menus";
  import { SpaceIdentityIcon } from "../../spaces/SpaceIdentity";
  import SymbolIcon from "../../SymbolIcon.svelte";
  import { useCoreVersion } from "../../use-core";
  import { explanation } from "../use-setup-space.svelte";

  /**
   * BrowserSetupSpacesPage: the Spaces Setup will make, each followed by its
   * Sub-Spaces and an Add Sub-Space, then New Space. A row opens its Space's
   * page; its menu moves a Space up or down, or removes one Setup added.
   */
  let { session, onOpenSpace }: { session: Session; onOpenSpace: (spaceId: string) => void } = $props();

  let error = $state<string | null>(null);
  const draft = $derived.by(() => (useCoreVersion(session), session.core.state.setupDraft));
  const primaries = $derived(draft?.spaces.filter((space) => space.primaryId === null) ?? []);

  const run = async (intent: Parameters<Session["core"]["send"]>[0]) => {
    try {
      await session.core.send(intent);
      error = null;
      return true;
    } catch (failure) {
      error = explanation(failure);
      return false;
    }
  };
  // A new Space or Sub-Space opens its page, as the Mac's does.
  const add = async (fromSpaceId: string | null) => {
    const before = new Set(draft?.spaces.map((space) => space.spaceId));
    if (!(await run(AddSetupSpace({ fromSpaceId })))) return;
    const added = session.core.state.setupDraft?.spaces.find((space) => !before.has(space.spaceId));
    if (added) onOpenSpace(added.spaceId);
  };
  const menu = (event: MouseEvent, space: SetupDraftSpace) => {
    event.preventDefault();
    const index = primaries.findIndex((primary) => primary.spaceId === space.spaceId);
    const entries: MenuEntry[] = [];
    if (index > 0) entries.push({ title: "Move Up", icon: "arrow.up", run: () => void run(MoveSetupSpace({ spaceId: space.spaceId, targetSpaceId: primaries[index - 1].spaceId })) });
    if (index >= 0 && index < primaries.length - 1) {
      entries.push({ title: "Move Down", icon: "arrow.down", run: () => void run(MoveSetupSpace({ spaceId: space.spaceId, targetSpaceId: primaries[index + 1].spaceId })) });
    }
    if (space.isNew) entries.push("separator", { title: "Remove Space", icon: "trash", run: () => void run(RemoveSetupSpace({ spaceId: space.spaceId })) });
    void showContextMenu(event, entries);
  };
</script>

{#snippet row(space: SetupDraftSpace, sub: boolean)}
  <button type="button" class={["setup-row setup-space-row", sub && "sub"]}
    aria-label={sub ? `${space.shownName}, Sub-Space` : space.shownName}
    onclick={() => onOpenSpace(space.spaceId)} oncontextmenu={(event) => menu(event, space)}>
    {#if sub}
      <SymbolIcon name="arrow.turn.down.right" size={11} strokeWidth={2.5} class="setup-sub-arrow" />
    {/if}
    <SpaceIdentityIcon symbol={space.customization.symbol} branding={space.customization.branding} size={sub ? 22 : 26} />
    <span class="setup-space-name">{space.shownName}</span>
    <SymbolIcon name="chevron.forward" size={11} strokeWidth={2.5} class="setup-disclosure" />
  </button>
{/snippet}

{#if !draft}
  <div class="setup-page-content"><h2 class="setup-page-heading">Spaces</h2></div>
{:else}
  <div class="setup-page-content">
    <h2 class="setup-page-heading">Spaces</h2>
    <section class="settings-group">
      <div class="settings-card setup-list">
        {#each primaries as primary (primary.spaceId)}
          {@render row(primary, false)}
          {#each draft.spaces.filter((space) => space.primaryId === primary.spaceId) as space (space.spaceId)}
            {@render row(space, true)}
          {/each}
          <span class="setup-list-item">
            <button type="button" class="setup-tertiary setup-add-sub-space" data-testid="setup-add-sub-space"
              aria-label="Add a Sub-Space to {primary.shownName}" onclick={() => void add(primary.spaceId)}>
              <SymbolIcon name="plus" size={13} strokeWidth={2.25} />Add Sub-Space
            </button>
          </span>
        {/each}
      </div>
      <p class="settings-footer">A Sub-Space shares its Space’s sign-ins and history, with tabs and a look of its own.</p>
    </section>
    <section class="settings-group">
      <div class="settings-card setup-list">
        <span class="setup-list-item">
          <button type="button" class="setup-tertiary" data-testid="setup-add-space" onclick={() => void add(null)}>
            <SymbolIcon name="plus" size={13} strokeWidth={2.25} />New Space
          </button>
        </span>
      </div>
    </section>
    {#if error}
      <p class="setup-error" role="alert">{error}</p>
    {/if}
  </div>
{/if}
