<script lang="ts">
  import { EngineCapability, LoadAddress, OpenPage, ReleasePage, TransientPresentation } from "@crest/contracts";
  import { untrack } from "svelte";

  import { pageContentId } from "../shell/PageCard.svelte";
  import { isLocked } from "../spaces/space-access";
  import { coreState } from "../use-core";
  import type { PaneProps } from "./panes.svelte";

  let { session, shownSpace }: PaneProps = $props();
  let id = $state<string | null>(null);
  let content = $state<string | null>(null);
  let failed = $state(false);
  const available = $derived(!!session.shell && !!coreState(session).engines?.engines.some(
    engine => engine.isDefault && engine.capabilities.includes(EngineCapability.featureFlags))
    && !isLocked(session.core, shownSpace));

  // The engine owns its flags page. The transient belongs to the Settings tab's
  // Space and profile and goes away when either changes or Settings closes.
  $effect(() => {
    const spaceId = shownSpace.id;
    void shownSpace.profileId;
    const allowed = available;
    return untrack(() => {
      id = null;
      content = null;
      failed = false;
      if (!allowed) return;
      const pageId = crypto.randomUUID();
      let disposed = false;
      let opened = false;
      const release = () => {
        if (!opened) return;
        opened = false;
        void session.core.send(ReleasePage({ pageId, keepsState: false })).catch(() => {});
      };
      void (async () => {
        try {
          await session.core.send(OpenPage({ pageId, workspaceId: session.workspaceId, spaceId,
            tabId: null, windowId: session.windowId, transient: TransientPresentation.settings, openerPageId: null }));
          opened = true;
          if (disposed) { release(); return; }
          id = pageId;
          await session.core.send(LoadAddress({ pageId, url: "crest://flags/" }));
        } catch {
          if (!disposed) { failed = true; id = null; }
          release();
        }
      })();
      return () => { disposed = true; release(); };
    });
  });
  const liveId = $derived(id && coreState(session).pages.get(id)?.phase.name === "live" ? id : null);
  $effect(() => {
    const pageId = liveId;
    if (!pageId) return;
    let current = true;
    void pageContentId(session, pageId).then(value => {
      if (current) { content = value; failed = !value; }
    }).catch(() => { if (current) failed = true; });
    return () => { current = false; };
  });
</script>

{#if !available || failed}
  <p class="settings-secondary-text">Feature Flags Unavailable</p>
{:else if content && liveId}
  <embed class="settings-engine-page" type="application/x-chromium-surface-embed" data-content-id={content} title="Chromium Feature Flags" />
{/if}
