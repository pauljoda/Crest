<script lang="ts" module>
  import { motion as tokens } from "@crest/design";
  import type { TransitionConfig } from "svelte/transition";

  import type { Session } from "../boot";
  import { presence, reducesMotion, timed } from "../motion";

  /** A Peek the window shows: a page the core opened for a link, over the page that followed it. */
  export interface Peek {
    /** The Peek's own page, transient until it is kept as a tab. */
    readonly pageId: string;
    readonly sourcePageId: string;
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
    readonly onComplete: () => void;
  }

  /**
   * The Mac's spring for a Peek coming out of its link and going back into it,
   * at its Peek animation time's default, 240 ms (BrowserPeekPace).
   */
  const peekSpring = { type: "spring", visualDuration: 0.24, bounce: 0.16 } as const;

  /** The scrim fading in as the Peek comes, at once under Reduce Motion. */
  function scrimEntrance() {
    return { pose: { opacity: 0 }, timing: reducesMotion() ? { duration: 0 } : tokens.floatingPane };
  }

  function scrimExit(animated: boolean) {
    return { pose: { opacity: 0 }, timing: animated && !reducesMotion() ? tokens.floatingPane : { duration: 0 } };
  }

  /**
   * The card coming out of its link: a whole transform, which runs on the
   * compositor, so the page loading beneath doesn't hold it up.
   */
  function stackEntrance() {
    return { pose: { scale: 0.08 }, timing: reducesMotion() ? { duration: 0 } : peekSpring, reduced: {} };
  }

  /**
   * Going back into the link, unless the Peek was kept as a tab, which leaves
   * at once: the card shrinks to nothing as it fades, gone by just over half
   * its way back. The scale follows the Peek's spring and the fade its own
   * curve, each from where the card stands as it starts to go.
   */
  function stackExit(node: Element, { animated }: { animated: boolean }): TransitionConfig {
    if (!animated || reducesMotion()) return presence(node, { pose: { opacity: 0 }, timing: { duration: 0 } });
    const spring = timed(peekSpring);
    const fade = timed({ duration: 0.22, ease: "easeOut" });
    const duration = Math.max(spring.duration, fade.duration);
    const style = getComputedStyle(node);
    const scale = style.transform === "none" ? 1 : new DOMMatrixReadOnly(style.transform).a;
    const opacity = Number(style.opacity);
    let start: number | null = null;
    return {
      duration,
      css: (t) => {
        // Svelte runs a going element's time from where any coming in had reached down to none.
        start ??= t;
        const elapsed = (start > 0 ? (start - t) / start : 1) * duration;
        const moved = spring.easing(Math.min(elapsed / spring.duration, 1));
        const faded = fade.easing(Math.min(elapsed / fade.duration, 1));
        return `transform: scale(${scale + (0.005 - scale) * moved}); opacity: ${opacity * (1 - faded)}`;
      },
    };
  }

  function sourceTitle(session: Session, peek: Peek): string {
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
  import { coreState, useCoreVersion } from "../use-core";
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

  const space = $derived(spaces.find((candidate) => candidate.id === peek.spaceId) ?? null);
  const page = $derived(coreState(session).pages.get(peek.pageId));
  // The page shows once it has committed something, a moment after, as the Mac's reveal does.
  const committed = $derived(!!page?.live.url);
  const tint = $derived(space ? backgroundColor(space.settings.look) : null);
  let menu = $state<HTMLButtonElement>();
  $effect(() => () => exit?.onComplete());

  // The Peek's page, embedded once the engine has it and taking the keyboard as it comes.
  let content = $state<string | null>(null);
  let element = $state<HTMLEmbedElement>();
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
  let reveal: Animation | null = null;
  $effect(() => {
    const embed = element;
    const shown = committed;
    if (!embed) return;
    const from = reveal ? Number(getComputedStyle(embed).opacity) : 0;
    reveal?.cancel();
    const reduce = reducesMotion();
    const { duration, delay, css: easing } = timed({ duration: 0.12, ease: "easeOut", delay: 0.034 });
    reveal = embed.animate([{ opacity: from }, { opacity: shown ? 1 : 0 }],
      { duration: reduce ? 0 : duration, delay: reduce ? 0 : delay, easing, fill: "both" });
  });
</script>

<div class={`peek-layer${hidden ? " hidden" : ""}`} inert={hidden} aria-hidden={hidden || undefined}>
  <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
  <div class="peek-scrim" aria-hidden="true" onclick={onClose}
    in:presence={scrimEntrance()} out:presence={scrimExit(exit?.animates ?? true)}></div>
  <div class="peek-stack" role="dialog" aria-label={`Peek from ${(useCoreVersion(session), sourceTitle(session, peek))}`}
    in:presence={stackEntrance()} out:stackExit={{ animated: exit?.animates ?? true }}>
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
      {/if}
    </div>
  </div>
</div>
