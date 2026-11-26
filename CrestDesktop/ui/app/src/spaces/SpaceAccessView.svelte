<script lang="ts">
  import type { SpaceState } from "@crest/contracts";
  import type { Snippet } from "svelte";

  import type { Session } from "../boot";
  import { css, primaryColor } from "../branding";
  import { showContextMenu } from "../menus";
  import PageCard from "../shell/PageCard.svelte";
  import SymbolIcon from "../SymbolIcon.svelte";
  import { useCoreVersion } from "../use-core";
  import { failureMessages, isAuthenticating, unlockSpace, useAccessFailure } from "./space-access";
  import { showSpace } from "./show-space";
  import { SpaceIdentityIcon } from "./SpaceIdentity";

  /**
   * BrowserSpaceAccessView as the page area's overlay: a locked Space's card
   * holds its crest with a lock, its name, "Space Locked", and Unlock, which
   * asks Windows Hello, with why the last try failed under it, and Switch
   * Space while there is another. None of the Space's pages show. `children`
   * layer over the row, as the window's notices do over its cards.
   */
  let { session, space, spaces, passive, children }: {
    session: Session;
    space: SpaceState;
    spaces: readonly SpaceState[];
    passive: boolean;
    children?: Snippet;
  } = $props();

  const failure = $derived(useAccessFailure());
  const authenticating = $derived((useCoreVersion(session), isAuthenticating(session.core, space.id)));
  const anyAuthenticating = $derived((useCoreVersion(session), isAuthenticating(session.core)));
  const others = $derived(spaces.filter((candidate) => candidate.id !== space.id));
</script>

{#snippet content()}
  <div class="space-access" data-testid="private-space-lock" style:--access-tint={css(primaryColor(space.settings.look), 0.1)}>
    <div class="space-access-content">
      <span class="space-access-icon">
        <SpaceIdentityIcon symbol={space.settings.symbol} branding={space.settings.look} size={64} />
        <span class="space-access-badge"><SymbolIcon name="lock.fill" size={16} /></span>
      </span>
      <div class="space-access-heading">
        <h1>{space.settings.name}</h1>
        <span class="space-access-status"><SymbolIcon name="lock.fill" size={11} />Space Locked</span>
      </div>
      <p>Unlock to view your tabs.</p>
      <button type="button" class="space-access-unlock" data-testid="unlock-private-space" disabled={passive || anyAuthenticating}
        aria-label={authenticating ? "Authenticating…" : `Unlock ${space.settings.name}`}
        onclick={() => void unlockSpace(session, space)}>
        {#if authenticating}
          <span class="space-access-spinner" aria-hidden="true"></span>
        {:else}
          <SymbolIcon name="lock.open.fill" size={13} />Unlock
        {/if}
      </button>
      <!-- The message keeps its room, so a failure never moves the button. -->
      <p class={["space-access-failure", !failure && "reserved"]} aria-live="polite">
        {failureMessages[failure ?? "unavailable"]}
      </p>
      {#if others.length > 0}
        <button type="button" class="space-access-switch" data-testid="switch-private-space" disabled={passive}
          onclick={(event) => {
            const bounds = event.currentTarget.getBoundingClientRect();
            void showContextMenu(session.shell, { clientX: bounds.left, clientY: bounds.bottom + 4 }, others.map((candidate) => ({
              title: candidate.settings.name,
              run: () => void showSpace(session.core, session.windowId, candidate.id).catch(() => undefined),
            })));
          }}>
          <SymbolIcon name="square.grid.2x2" size={13} />Switch Space
        </button>
      {/if}
    </div>
  </div>
{/snippet}

<div class="page-columns">
  <div class="page-column focused">
    <PageCard {session} pageId={null} {passive} startPage={content} />
  </div>
  {@render children?.()}
</div>
