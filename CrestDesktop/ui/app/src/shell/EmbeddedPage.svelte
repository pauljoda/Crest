<script lang="ts">
  import { untrack } from "svelte";

  import type { Session } from "../boot";
  import { useCoreVersion } from "../use-core";
  import { focusShownPage, knownContentId, pageContentId } from "./PageCard.svelte";

  /**
   * A page embedded in its card. Asleep beneath its still while a slide brings
   * the card on screen, the embed stands unseen, which the engine takes as the
   * page hidden, so the page neither draws nor gives up its place: it wakes in
   * the same embedding as the strip lands, and its drawing from then on is that
   * embedding's, which the engine pictures it from.
   */
  let { session, pageId, passive, asleep = false }: {
    session: Session;
    pageId: string | null;
    passive: boolean;
    asleep?: boolean;
  } = $props();

  const live = $derived(pageId ? (useCoreVersion(session), session.core.state.pages.get(pageId)?.phase.name === "live") : false);
  let embedded = $state.raw<{ page: string; content: string } | null>(untrack(() => {
    const known = pageId && live ? knownContentId(pageId) : undefined;
    return known && pageId ? { page: pageId, content: known } : null;
  }));
  $effect(() => {
    const id = pageId;
    const isLive = live;
    if (!id || !isLive || embedded?.page === id) return;
    const cached = knownContentId(id);
    if (cached) {
      embedded = { page: id, content: cached };
      return;
    }
    let current = true;
    void pageContentId(session, id).then((content) => {
      if (content && current) embedded = { page: id, content };
    });
    return () => {
      current = false;
    };
  });
  // A page the window comes to show takes the keyboard, unless one of the
  // interface's own fields holds it; so does a split's card as it becomes
  // the focused one, from the page that had it.
  const shown = $derived(embedded && embedded.page === pageId && !passive ? embedded.page : null);
  let element = $state<HTMLEmbedElement>();
  $effect(() => {
    const embed = element;
    if (!shown) return;
    untrack(() => {
      const active = document.activeElement;
      if (!active || active === document.body) focusShownPage();
      else if (active instanceof HTMLEmbedElement && active !== embed) embed?.focus();
    });
  });
</script>

{#if embedded && embedded.page === pageId}
  {#key embedded.page}
    <embed
      bind:this={element}
      class="page-frame"
      type="application/x-chromium-surface-embed"
      data-content-id={embedded.content}
      tabindex={-1}
      style:visibility={asleep ? "hidden" : undefined}
    />
  {/key}
{/if}
