<script lang="ts" module>
  import { ApplyManualSetup, ImportPreview, type SpaceState } from "@crest/contracts";
  import { untrack } from "svelte";

  import type { Session } from "../boot";
  import { useCoreVersion } from "../use-core";

  /** BrowserSetupLiveSessionMetrics.changeInterval: the preview takes the newest draft at most this often. */
  const changeInterval = 66;

  /**
   * The Spaces Setup will make, as the core would open them once it applies
   * the draft (ImportPreview of ApplyManualSetup), asked again as the draft
   * changes, the first change at once and the newest at most every 66 ms.
   * Call during a component's initialization, and read `.current`.
   */
  export function usePreviewSpaces(session: Session): { readonly current: readonly SpaceState[] } {
    const draft = $derived.by(() => (useCoreVersion(session), session.core.state.setupDraft));
    let spaces = $state.raw<readonly SpaceState[]>([]);
    let last = 0;
    let timer: number | null = null;
    $effect(() => {
      if (!draft) return;
      untrack(() => {
        const ask = () => {
          timer = null;
          last = performance.now();
          session.core.query(ImportPreview({ import: ApplyManualSetup({ workspaceId: session.workspaceId, windowId: session.windowId }) }))
            .then((preview) => {
              spaces = preview.session.spaces;
            }, () => undefined);
        };
        if (timer !== null) return;
        const wait = Math.max(0, changeInterval - (performance.now() - last));
        if (wait === 0) ask();
        else timer = window.setTimeout(ask, wait);
      });
    });
    $effect(() => () => {
      if (timer !== null) clearTimeout(timer);
    });
    return {
      get current() {
        return spaces;
      },
    };
  }
</script>

<script lang="ts">
  import { readsLight } from "../branding";
  import ChromeButton from "../shell/ChromeButton.svelte";
  import { SpaceBanner } from "../shell/SpaceBanner";
  import StartPage from "../shell/StartPage.svelte";
  import { SpaceIdentityIcon } from "../spaces/SpaceIdentity";
  import SpaceSwitcher from "../spaces/SpaceSwitcher.svelte";
  import SymbolIcon from "../SymbolIcon.svelte";

  /**
   * BrowserSetupLiveWindow, as Windows can draw it: Crest's window for the
   * Space Setup shows, at its real size, wearing that Space's look, with its
   * sidebar, its Spaces in the switcher and its Start Page. The Mac runs a
   * second core for a preview the person can use; Windows' host holds one, so
   * this one is still, and only follows the draft.
   */
  let { spaces, shownSpaceId }: { spaces: readonly SpaceState[]; shownSpaceId: string | null } = $props();

  const space = $derived(spaces.find((each) => each.id === shownSpaceId) ?? spaces[0]);
</script>

{#if space}
  {@const look = space.settings.look}
  <div class="browser-window with-title-bar {readsLight(look) ? 'reads-light' : 'reads-dark'} sidebar-docked setup-preview-window"
    role="img" aria-label="Preview of Crest">
    <SpaceBanner {spaces} spaceId={space.id} />
    <div class="sidebar-slot docked">
      <aside class="sidebar">
        <div class="address-area">
          <div class="address-field">
            <span class="address-progress" aria-hidden="true"></span>
            <span class="address-summary"><span class="address-domain placeholder">Search or enter website</span></span>
          </div>
        </div>
        <div class="space-pages">
          <div class="space-page">
            <div class="space-header without-pins">
              <span class="space-header-title">
                <span class="space-header-identity">
                  <span class="space-header-crest">
                    <SpaceIdentityIcon symbol={space.settings.symbol} branding={look} size={20} />
                  </span>
                </span>
                <span class="space-name">{space.settings.name}</span>
              </span>
              <ChromeButton symbol="ellipsis" label="Space Actions" className="space-header-actions" />
            </div>
            <div class="tab-list">
              <section class="tab-section current-tabs">
                <span class="sidebar-row new-tab-row">
                  <span class="row-glyph"><SymbolIcon name="plus" size={14} /></span>
                  <span class="row-title">New Tab</span>
                </span>
              </section>
            </div>
          </div>
        </div>
        <SpaceSwitcher {spaces} selectedId={space.id} onSelect={() => {}}>
          {#snippet leading()}
            <ChromeButton symbol="sidebar.left" label="Hide Sidebar" />
          {/snippet}
          {#snippet trailing()}
            <ChromeButton symbol="archivebox" label="Archive" className="common-lists-button" />
          {/snippet}
        </SpaceSwitcher>
      </aside>
    </div>
    <div class="space-content">
      <div class="space-content-page live">
        <div class="page-columns">
          <div class="page-column focused">
            <main class="page-card clear">
              <StartPage palette={null} isPrivate={false} bindings={[]} tabs={[]} obscured={false} takesFocus={false} />
            </main>
          </div>
        </div>
      </div>
    </div>
    <header class="title-bar">
      <div class="title-bar-navigation">
        <ChromeButton symbol="chevron.left" label="Back" disabled className="navigation-button" size={23} />
        <ChromeButton symbol="chevron.right" label="Forward" disabled className="navigation-button" size={23} />
        <ChromeButton symbol="arrow.clockwise" label="Reload" disabled className="navigation-button" size={18} />
      </div>
      <span class="title-bar-drag"></span>
      <!-- Windows' own caption buttons, dimmed, where the Mac's preview dims its traffic lights. -->
      <div class="window-controls inactive" aria-hidden="true">
        <span class="window-control"></span>
        <span class="window-control"></span>
        <span class="window-control close"></span>
      </div>
    </header>
  </div>
{/if}
