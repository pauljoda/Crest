<script lang="ts" module>
  import type { Timing } from "../motion";

  /** What the row hands each card it draws. */
  export interface ColumnCard {
    /** Whether the card is the one the window's chrome speaks for. */
    readonly focused: boolean;
    /** How the card moves into the place the row gives it. */
    readonly transition: Timing;
  }

  /** The row's slots, and the gaps between them, in the order they lie. */
  type Entry =
    | { readonly kind: "member"; readonly key: string; readonly tabId: string; readonly share: number }
    | { readonly kind: "placeholder"; readonly key: "placeholder"; readonly share: number }
    | { readonly kind: "divider"; readonly key: string; readonly divider: number | null };
  type Member = Extract<Entry, { kind: "member" }>;
  type Placeholder = Extract<Entry, { kind: "placeholder" }>;
  type Gap = Extract<Entry, { kind: "divider" }>;

  /** A change the row takes at once. */
  const instant: Timing = { duration: 0 };
</script>

<script lang="ts">
  import type { BrandColor } from "@crest/contracts";
  import { motion as tokens } from "@crest/design";
  import { type Snippet, untrack } from "svelte";

  import { css } from "../branding";
  import { presence } from "../motion";
  import SymbolIcon from "../SymbolIcon.svelte";
  import { useCardsSnap } from "./cards-snap";
  import { usePointerHeld } from "./pointer-hold";
  import { liftOut, RowMotion } from "./row-motion";
  import { CardIdentities, sameMembers, type SpaceCards, sharesAfterResize, sharesDiffer, sharesInserting } from "./shown-cards";
  import SplitDivider from "./SplitDivider.svelte";
  import { useSplitDropIndex } from "./split-drop";

  /**
   * The Mac's BrowserSplitColumnsView: the cards a window shows for a Space in
   * a row, a Split View's members side by side or a tab alone, with the page
   * frame's gap between them and a divider in each gap. Widths are the
   * columns' shares of the row once the gaps are paid for, none narrower than
   * the minimum, as flexible boxes lay them out, and a row too narrow for every
   * card clips. A card joining, leaving or moving settles with the row's
   * motion; another tab shown alone lands at once, as a tab switch does; a
   * resize tracks the pointer and keeps its shares once, on release. The card
   * the window's chrome speaks for wears the Space's colour while there is
   * more than one.
   */
  let { windowId, cards, focusedTabId, accent, interactive, onFocus, onResize, renderCard, children }: {
    /** The window the row is in, whose sidebar's lift may draw a drop column in it. */
    windowId: string;
    cards: SpaceCards;
    focusedTabId: string | null;
    accent: BrandColor;
    /** Whether the row is the window's own, which focuses and resizes, rather than another Space's in passing. */
    interactive: boolean;
    /** Makes a card the focused one; `byPointer` when the pointer only moved onto it. */
    onFocus: (tabId: string, byPointer: boolean) => void;
    /** Keeps the shares a divider drag settled on. */
    onResize: (shares: readonly number[]) => Promise<unknown>;
    renderCard: Snippet<[tabId: string, card: ColumnCard]>;
    /** What layers over the whole row, such as the window's notices. */
    children?: Snippet;
  } = $props();

  const identities = new CardIdentities();
  const identity = $derived.by(() => {
    const keys = identities.cards(cards.tabIds);
    return { keys, settles: identities.settles };
  });
  const held = $derived(usePointerHeld());
  const snaps = $derived(useCardsSnap());
  let row = $state<HTMLDivElement>();

  // The shares a drag is writing, and then the ones it kept until the core's arrive.
  let dragged = $state.raw<readonly number[] | null>(null);
  const storedShares = $derived(cards.shares.join());
  const memberCount = $derived(cards.tabIds.length);
  $effect(() => {
    void storedShares;
    void memberCount;
    dragged = null;
  });
  const shares = $derived(dragged && dragged.length === cards.tabIds.length ? dragged : cards.shares);

  // Where a lift from the sidebar would join the cards: a column of the
  // width the card will have, drawn before it lands.
  const placeholder = $derived.by(() => {
    const aimed = useSplitDropIndex(windowId);
    return interactive && aimed !== null && aimed <= cards.tabIds.length ? aimed : null;
  });
  const slotShares = $derived(placeholder === null ? shares : sharesInserting(placeholder, shares));
  const several = $derived(cards.tabIds.length > 1);

  // The row's slots: each member's card, and the drop column where a lift
  // aims; and between each two, the gap a divider stands in, which belongs
  // to the slot before it.
  const entries = $derived.by(() => {
    type Slot = { readonly kind: "member"; readonly tabId: string; readonly member: number } | { readonly kind: "placeholder" };
    const slots: Slot[] = cards.tabIds.map((tabId, member) => ({ kind: "member", tabId, member }));
    if (placeholder !== null) slots.splice(placeholder, 0, { kind: "placeholder" });
    const slotKey = (slot: Slot) => (slot.kind === "member" ? identity.keys.get(slot.tabId)! : "placeholder");
    const drawn: Entry[] = [];
    slots.forEach((slot, index) => {
      if (index > 0) {
        const before = slots[index - 1];
        // A gesture in flight has no dividers: the pointer is the gesture's.
        const divider = before.kind === "member" && slot.kind === "member" && placeholder === null ? before.member : null;
        drawn.push({ kind: "divider", key: `divider-${slotKey(before)}`, divider });
      }
      drawn.push(slot.kind === "member"
        ? { kind: "member", key: slotKey(slot), tabId: slot.tabId, share: slotShares[index] }
        : { kind: "placeholder", key: "placeholder", share: slotShares[index] });
    });
    return drawn;
  });
  /** What lays the row out: its slots, their widths, and whether it is a split. */
  const layout = $derived(`${entries.map((entry) => `${entry.key} ${"share" in entry ? entry.share : ""}`).join()}`
    + `${several ? " several" : ""}${placeholder !== null ? " split" : ""}`);

  // A change of members settles with the row's motion, or lands at once for a
  // tab switch, and so does the drop column opening, moving and closing;
  // anything else that moves the cards moves them with the window's chrome.
  // A drag holding the pointer moves them at once, and so does the sidebar
  // taking its seat or leaving it, the page's edge following the sidebar's (`cards-snap.ts`).
  // The row settles its motion for each change before Svelte draws it, and
  // measures what the change moves, which it moves once drawn (`row-motion.ts`).
  let drawn: { members: readonly string[]; placeholder: number | null } = { members: [], placeholder: null };
  let transition = $state.raw<Timing>(tokens.chrome);
  let measured = $state(0);
  const motion = new RowMotion();
  $effect.pre(() => {
    const members = cards.tabIds;
    const aimed = placeholder;
    const dragging = dragged !== null;
    const pointerHeld = held;
    const snapping = snaps;
    const { settles } = identity;
    void layout;
    untrack(() => {
      const membersChanged = !sameMembers(drawn.members, members);
      const placeholderChanged = drawn.placeholder !== aimed;
      drawn = { members, placeholder: aimed };
      transition = dragging ? instant
        : membersChanged ? (settles ? tokens.collection : instant)
          : placeholderChanged ? tokens.collection : pointerHeld || snapping ? instant : tokens.chrome;
      motion.measure(row);
      measured += 1;
    });
  });
  $effect(() => {
    void measured;
    untrack(() => motion.settle(transition));
  });
</script>

{#snippet member(entry: Entry)}
  {@const slot = entry as Member}
  {@const focused = slot.tabId === focusedTabId}
  <!-- A press in a card, or its page taking the keys, focuses it, and the event goes on to the page. -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    class={`page-column${focused ? " focused" : ""}`}
    data-tab-id={slot.tabId}
    style:flex-grow={slot.share}
    in:presence={{ pose: { opacity: 0 }, timing: tokens.collection }}
    out:liftOut={{ pose: { opacity: 0 }, timing: tokens.collection }}
    onpointerdowncapture={() => interactive && onFocus(slot.tabId, false)}
    onfocusincapture={() => interactive && onFocus(slot.tabId, false)}
    onpointerenter={() => interactive && onFocus(slot.tabId, true)}
  >
    {@render renderCard(slot.tabId, { focused, transition })}
  </div>
{/snippet}

{#snippet dropColumn(entry: Entry)}
  <!-- The drag that summoned it owns every event, so the column takes none. -->
  <div class="page-column page-placeholder" style:flex-grow={(entry as Placeholder).share} aria-label="Add to Split View"
    in:presence={{ pose: { opacity: 0 }, timing: tokens.collection }}
    out:liftOut={{ pose: { opacity: 0 }, timing: tokens.collection }}>
    <div class="page-placeholder-card">
      <SymbolIcon name="rectangle.split.2x1" size={22} strokeWidth={1.5} />
      <span>Add to Split View</span>
    </div>
  </div>
{/snippet}

{#snippet gap(entry: Entry)}
  {@const divider = (entry as Gap).divider}
  <SplitDivider index={divider ?? 0} interactive={interactive && !held && divider !== null}
    shows={divider !== null} {shares} {transition}
    resize={(delta, baseline) => {
      if (divider === null) return;
      const width = row?.clientWidth ?? 0;
      dragged = sharesAfterResize(baseline, divider, delta, width);
    }}
    commit={(next) => {
      if (!cards.groupId || !sharesDiffer(next, cards.shares)) {
        dragged = null;
        return;
      }
      void onResize(next).finally(() => (dragged = null));
    }} />
{/snippet}

<!-- The focused card's ring, in the Space's colour, is its outline (styles.css). -->
<div bind:this={row} class={`page-columns${several || placeholder !== null ? " split" : ""}${several ? " several" : ""}`}
  style:--split-accent={css(accent, 0.9)}
  role={several ? "group" : undefined} aria-label={several ? "Split View Columns" : undefined}>
  <!-- Each slot and gap is the row's own child, so what comes and goes with it plays as it does. -->
  {#each entries as entry (entry.key)}
    {@render (entry.kind === "divider" ? gap : entry.kind === "placeholder" ? dropColumn : member)(entry)}
  {/each}
  {@render children?.()}
</div>
