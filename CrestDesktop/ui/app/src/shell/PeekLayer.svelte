<script lang="ts" module>
  import { motion as tokens, springCurve } from "@crest/design";
  import type { TransitionConfig } from "svelte/transition";

  import { peekSize, peekTime } from "../appearance.svelte";
  import { useLinkPreferences } from "../settings/preferences.svelte";
  import type { Session } from "../boot";
  import { presence, reducesMotion, timed } from "../motion";

  /** A Peek the window shows: a page the core opened for a link, over the page that followed it. */
  export interface Peek {
    /** The Peek's own page, transient until it is kept as a tab. */
    readonly pageId: string;
    readonly sourcePageId: string | null;
    readonly sourceTabId: string;
    /** The Space the link was followed in, which Open In keeps the page in. */
    readonly spaceId: string;
    readonly url: string;
  }

  /**
   * How a Peek goes, which the window says as it closes it, as Motion's
   * `AnimatePresence` told its leaving children with `custom`, and what it
   * hears once the Peek has gone, as its `onExitComplete`.
   */
  export interface PeekExit {
    /** Whether the Peek goes back into its link, rather than at once, as one kept as a tab does. */
    readonly animates: boolean;
    readonly pickup: number;
    readonly onComplete: (pageId: string) => void;
  }

  function snaps() { return reducesMotion() || peekTime.current === 0; }

  function scrimEntrance() {
    return { pose: { opacity: 0 }, timing: snaps() ? { duration: 0 } : tokens.floatingPane };
  }

  function scrimExit(exit?: PeekExit) {
    const timing = (exit?.animates ?? true) && !snaps() ? { ...tokens.floatingPane, delay: (exit?.pickup ?? 0) / 1000 } : { duration: 0 };
    return { pose: { opacity: 0 }, timing };
  }

  // BrowserTransientMotion samples the spring for twice its perceptual duration.
  // On the return journey the opacity falls linearly over 92% of that duration.
  function moveStack(node: Element, returning: boolean, exit?: PeekExit): TransitionConfig {
    if (exit?.animates === false || snaps()) return { duration: 0 };
    const length = peekTime.current;
    const spring = springCurve({ type: "spring", visualDuration: length / 1000, bounce: 0.16 });
    const style = getComputedStyle(node);
    const from = returning ? (style.transform === "none" ? 1 : new DOMMatrixReadOnly(style.transform).a) : 0.08;
    const to = returning ? 0.005 : 1;
    const opacity = Number(style.opacity);
    return {
      delay: exit?.pickup ?? 0,
      duration: length * 2,
      css: t => {
        const elapsed = (returning ? 1 - t : t) * length * 2;
        const scale = elapsed >= length * 2 ? to : Math.max(0.001, from + (to - from) * spring.position(elapsed / 1000));
        const alpha = returning ? Math.max(0, 1 - elapsed / (length * 0.92)) * opacity : 1;
        return `transform: scale(${scale}); opacity: ${alpha}`;
      },
    };
  }
  const stackEntrance = (node: Element) => moveStack(node, false);
  const stackExit = (node: Element, exit?: PeekExit) => moveStack(node, true, exit);

  function sourceTitle(session: Session, peek: Peek): string {
    if (!peek.sourcePageId) return "Settings";
    const source = session.core.state.pages.get(peek.sourcePageId);
    return source?.live.title || source?.live.url || "page";
  }
</script>

<script lang="ts">
  import type { SpaceState } from "@crest/contracts";

  import { backgroundColor, css, toneOver } from "../branding";
  import { showContextMenu } from "../menus";
  import { SpaceIdentityIcon } from "../spaces/SpaceIdentity";
  import SymbolIcon from "../SymbolIcon.svelte";
  import { coreState, useCoreVersion, useEngineVersion } from "../use-core";
  import { pageContentId } from "./PageCard.svelte";

  /**
   * The Mac's Peek in its pointer arrangement: the Space's page area dimmed,
   * and over it, inset by 24, the action bar above a card holding the Peek's
   * page. The card grows out of where the link was, the middle of the page
   * area here since the page keeps where it was pressed to itself, and goes
   * back into it as it closes. Clicking outside the card closes it; Open In
   * keeps its page as a tab of the Space it came from, or of another Space
   * its menu names.
   */
  let { session, peek, spaces, hidden, onClose, onOpenIn, exit }: {
    session: Session;
    peek: Peek;
    spaces: readonly SpaceState[];
    /** Whether the Peek waits unseen while the window shows another tab than its link's. */
    hidden: boolean;
    onClose: () => void;
    onOpenIn: (spaceId: string) => void;
    /** How it goes, and what hears it gone. */
    exit?: PeekExit;
  } = $props();

  const links = useLinkPreferences(() => session);
  const space = $derived(spaces.find((candidate) => candidate.id === peek.spaceId) ?? null);
  const page = $derived(coreState(session).pages.get(peek.pageId));
  // The page shows once it has committed something, a moment after, as the Mac's reveal does.
  const framed = $derived((useEngineVersion(session), session.engine?.pages.get(peek.pageId)?.url));
  const committed = $derived(!!page?.live.url);
  const tint = $derived(space ? backgroundColor(space.settings.look) : null);
  let menu = $state<HTMLButtonElement>();
  $effect(() => {
    const pageId = peek.pageId;
    return () => exit?.onComplete(pageId);
  });

  // The Peek's page, embedded once the engine has it and taking the keyboard as it comes.
  let content = $state<string | null>(null);
  let element = $state<HTMLEmbedElement | HTMLIFrameElement>();
  let loadedFrame = $state<HTMLIFrameElement>();
  const live = $derived(page?.phase.name === "live");
  $effect(() => {
    const pageId = peek.pageId;
    if (!session.shell || !live || content) return;
    let current = true;
    void pageContentId(session, pageId).then((id) => {
      if (current && id) content = id;
    });
    return () => {
      current = false;
    };
  });
  $effect(() => {
    if (content) element?.focus();
  });
  // It comes in unseen and fades in once the page has committed something,
  // from wherever its fade stands.

  $effect(() => {
    const embed = element;
    if (!embed || !committed || (embed instanceof HTMLIFrameElement && loadedFrame !== embed)) return;
    const reduce = reducesMotion();
    const { duration, delay, css: easing } = timed({ duration: 0.12, ease: "easeOut", delay: 0.034 });
    const reveal = embed.animate([{ opacity: 0 }, { opacity: 1 }],
      { duration: reduce ? 0 : duration, delay: reduce ? 0 : delay, easing, fill: "both" });
    return () => reveal.cancel();
  });
</script>

<div class={`peek-layer${hidden ? " hidden" : ""}`} inert={hidden} aria-hidden={hidden || undefined}>
  <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
  <div class="peek-scrim" style:background={links.current?.dimsPageBehindPeek === false ? "transparent" : undefined} aria-hidden="true" onclick={onClose}
    in:presence={scrimEntrance()} out:presence={scrimExit(exit)}></div>
  <div class="peek-stack" role="dialog" aria-label={`Peek from ${(useCoreVersion(session), sourceTitle(session, peek))}`}
    style:--peek-share={peekSize.current / 100}
    in:stackEntrance out:stackExit={exit}>
    <div class="peek-bar">
      <button class="peek-close" aria-label="Close Peek" title="Close Peek (Esc or Ctrl+W)" onclick={onClose}>
        <SymbolIcon name="xmark" size={18} strokeWidth={2.4} />
      </button>
      <div class={`peek-destination${tint && toneOver(tint) === "light" ? " reads-light" : ""}`}
        style:--peek-tint={tint ? css(tint, 0.72) : undefined}>
        <button class="peek-open-in" aria-label="Open In…" {...{ "aria-description": space?.settings.name ?? "Space" }}
          title={`Open in ${space?.settings.name ?? "Space"}`} onclick={() => onOpenIn(peek.spaceId)}>
          {#if space}
            <SpaceIdentityIcon symbol={space.settings.symbol} branding={space.settings.look} size={22} />
          {:else}
            <SymbolIcon name="square.grid.2x2" size={18} />
          {/if}
          <span>Open In…</span>
        </button>
        <span class="peek-destination-separator" aria-hidden="true"></span>
        <button bind:this={menu} class="peek-destination-menu" aria-label="Choose Destination Space"
          {...{ "aria-description": space?.settings.name ?? "Space" }} title="Open in another Space"
          onclick={() => {
            const bounds = menu?.getBoundingClientRect();
            if (!bounds) return;
            void showContextMenu(session.shell, { clientX: bounds.left, clientY: bounds.bottom },
              spaces.map((candidate) => ({ title: candidate.settings.name, run: () => onOpenIn(candidate.id) })));
          }}>
          <SymbolIcon name="chevron.down" size={11} strokeWidth={2.6} />
        </button>
      </div>
    </div>
    <div class="peek-card">
      {#if content}
        <embed bind:this={element} class="page-frame" type="application/x-chromium-surface-embed" data-content-id={content}
          tabindex={-1} />
      {:else if !session.shell && framed}
        {#key framed}
          <iframe bind:this={element} class="page-frame" sandbox="allow-forms allow-scripts" src={framed} title="Peek"
            onload={event => { if (event.currentTarget instanceof HTMLIFrameElement) loadedFrame = event.currentTarget; }}></iframe>
        {/key}
      {/if}
    </div>
  </div>
</div>
