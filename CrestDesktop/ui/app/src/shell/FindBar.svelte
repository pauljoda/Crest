<script lang="ts">
  import type { CrestCore } from "@crest/core-client";

  import SymbolIcon from "../SymbolIcon.svelte";
  import { focusShownPage } from "./PageCard.svelte";
  import { type FindSession, pageTools, usePageTools } from "./page-tools";

  /**
   * Find in page, as the Mac's BrowserFindBar floats it over the page's top
   * trailing corner: the query, what the search found, the previous and next
   * match, and close. Every ask for find is a request for the field, even
   * while the bar shows; a bar finding again brings back leaves the keys with
   * the page. Return finds the next match and Shift+Return the previous;
   * Escape closes the bar and gives the page the keyboard back.
   */
  let { core, pageId }: { core: CrestCore; pageId: string } = $props();

  const session = $derived(usePageTools().find(pageId));
  const presented = $derived(session.presented);
  const focusRequest = $derived(session.focusRequest);
  const focusesQueryField = $derived(session.focusesQueryField);
  let field = $state<HTMLInputElement>();
  $effect(() => {
    const input = field;
    const asked = presented && focusesQueryField;
    void focusRequest;
    if (!asked) return;
    input?.focus();
    input?.select();
  });

  const close = () => {
    pageTools.dismiss(core, pageId);
    requestAnimationFrame(focusShownPage);
  };
  // A key that composes text, as an input method's Enter does, is the field's.
  const onKeyDown = (event: KeyboardEvent) => {
    if (event.isComposing) return;
    if (event.key === "Escape") {
      event.preventDefault();
      close();
    } else if (event.key === "Enter" && event.target === field && !event.ctrlKey && !event.altKey && !event.metaKey) {
      event.preventDefault();
      pageTools.search(core, pageId, session.query, event.shiftKey);
    }
  };
  const hasQuery = $derived(session.query !== "");
</script>

<!--
  What the page can say about the search, in words, as the Mac's pointer
  shells spell it: "3 of 12" where the engine counts, else the state, red
  only where the page has nothing to show; nothing before a search.
-->
{#snippet matchStatus(session: FindSession)}
  {@const counted = session.matchState === "found" ? session.matches : null}
  {@const label = { idle: null, searching: "Searching", found: "Match found", notFound: "No match" }[session.matchState]}
  {#if counted}
    <span class="find-status" aria-label={`Match ${counted.active} of ${counted.total}`} data-testid="find-result">
      {counted.active} of {counted.total}
    </span>
  {:else if !label}
    <span class="find-status"></span>
  {:else}
    <span class={`find-status${session.matchState === "notFound" ? " failure" : ""}`} data-testid="find-result">
      {label}
    </span>
  {/if}
{/snippet}

{#if presented}
  <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
  <div class="find-bar" role="search" aria-label="Find in Page" data-testid="find-bar" onkeydown={onKeyDown}>
    <!-- Typing searches; the same text written back does not. -->
    <input
      bind:this={field}
      class="find-field"
      placeholder="Find in Page"
      aria-label="Find in Page"
      spellcheck={false}
      autocomplete="off"
      value={session.query}
      oninput={(event) => event.currentTarget.value !== session.query && pageTools.search(core, pageId, event.currentTarget.value)}
    />
    {@render matchStatus(session)}
    <button type="button" class="find-control" title="Previous Match" aria-label="Previous Match" disabled={!hasQuery}
      onclick={() => pageTools.search(core, pageId, session.query, true)}>
      <SymbolIcon name="chevron.up" size={13} />
    </button>
    <button type="button" class="find-control" title="Next Match" aria-label="Next Match" disabled={!hasQuery}
      onclick={() => pageTools.search(core, pageId, session.query)}>
      <SymbolIcon name="chevron.down" size={13} />
    </button>
    <button type="button" class="find-control" title="Close Find" aria-label="Close Find" onclick={close}>
      <SymbolIcon name="xmark" size={12} />
    </button>
  </div>
{/if}
