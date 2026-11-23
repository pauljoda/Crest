import type { BrandColor } from "@crest/contracts";
import { motion as tokens } from "@crest/design";
import { AnimatePresence, motion, type Transition } from "motion/react";
import { type CSSProperties, type ReactNode, type Ref, useEffect, useLayoutEffect, useRef, useState } from "react";

import { css } from "../branding";
import { Symbol } from "../symbols";
import { useCardsSnap } from "./cards-snap";
import { holdLiveResize } from "./PageCard";
import { holdPointer, usePointerHeld } from "./pointer-hold";
import { CardIdentities, sameMembers, type SpaceCards, sharesAfterResize, sharesDiffer, sharesInserting, splitMetrics } from "./shown-cards";
import { useSplitDropIndex } from "./split-drop";

/** What the row hands each card it draws. */
export interface ColumnCard {
  /** Whether the card is the one the window's chrome speaks for. */
  readonly focused: boolean;
  /** How the card moves into the place the row gives it. */
  readonly transition: Transition;
}

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
export function PageColumns({ windowId, cards, focusedTabId, accent, interactive, onFocus, onResize, renderCard, children }: {
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
  renderCard: (tabId: string, card: ColumnCard) => ReactNode;
  /** What layers over the whole row, such as the window's notices. */
  children?: ReactNode;
}) {
  const identities = useRef(new CardIdentities());
  const keys = identities.current.cards(cards.tabIds);
  const settles = identities.current.settles;
  const held = usePointerHeld();
  const snaps = useCardsSnap();
  const row = useRef<HTMLDivElement>(null);

  // The shares a drag is writing, and then the ones it kept until the core's arrive.
  const [dragged, setDragged] = useState<readonly number[] | null>(null);
  const storedShares = cards.shares.join();
  useEffect(() => setDragged(null), [storedShares, cards.tabIds.length]);
  const shares = dragged && dragged.length === cards.tabIds.length ? dragged : cards.shares;

  // Where a lift from the sidebar would join the cards: a column of the
  // width the card will have, drawn before it lands.
  const aimed = useSplitDropIndex(windowId);
  const placeholder = interactive && aimed !== null && aimed <= cards.tabIds.length ? aimed : null;
  const slotShares = placeholder === null ? shares : sharesInserting(placeholder, shares);

  // A change of members settles with the row's motion, or lands at once for a
  // tab switch, and so does the drop column opening, moving and closing;
  // anything else that moves the cards moves them with the window's chrome.
  // A drag holding the pointer moves them at once, and so does the sidebar
  // taking its seat or leaving it, the page's edge following the sidebar's (`cards-snap.ts`).
  const drawn = useRef<{ members: readonly string[]; placeholder: number | null }>({ members: [], placeholder: null });
  const membersChanged = !sameMembers(drawn.current.members, cards.tabIds);
  const placeholderChanged = drawn.current.placeholder !== placeholder;
  useLayoutEffect(() => {
    drawn.current = { members: cards.tabIds, placeholder };
  });
  const transition: Transition = dragged ? { duration: 0 }
    : membersChanged ? (settles ? tokens.collection : { duration: 0 })
      : placeholderChanged ? tokens.collection : held || snaps ? { duration: 0 } : tokens.chrome;
  const several = cards.tabIds.length > 1;

  // The row's slots: each member's card, and the drop column where a lift aims.
  type Slot = { readonly kind: "member"; readonly tabId: string; readonly member: number } | { readonly kind: "placeholder" };
  const slots: Slot[] = cards.tabIds.map((tabId, member) => ({ kind: "member", tabId, member }));
  if (placeholder !== null) slots.splice(placeholder, 0, { kind: "placeholder" });
  const slotKey = (slot: Slot) => (slot.kind === "member" ? keys.get(slot.tabId)! : "placeholder");

  return (
    // The focused card's ring, in the Space's colour, is its outline (styles.css).
    <div ref={row} className={`page-columns${several || placeholder !== null ? " split" : ""}${several ? " several" : ""}`}
      style={{ "--split-accent": css(accent, 0.9) } as CSSProperties}
      role={several ? "group" : undefined} aria-label={several ? "Split View Columns" : undefined}>
      <AnimatePresence initial={false} mode="popLayout">
        {slots.flatMap((slot, index) => {
          const column = slot.kind === "placeholder" ? (
            // The drag that summoned it owns every event, so the column takes none.
            <motion.div key="placeholder" className="page-column page-placeholder" style={{ flexGrow: slotShares[index] }}
              aria-label="Add to Split View" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
              transition={tokens.collection}>
              <motion.div className="page-placeholder-card" layout transition={transition}>
                <Symbol name="rectangle.split.2x1" size={22} strokeWidth={1.5} />
                <span>Add to Split View</span>
              </motion.div>
            </motion.div>
          ) : (() => {
            const focused = slot.tabId === focusedTabId;
            const tabId = slot.tabId;
            return (
              <motion.div
                key={slotKey(slot)}
                className={`page-column${focused ? " focused" : ""}`}
                data-tab-id={tabId}
                style={{ flexGrow: slotShares[index] }}
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                transition={tokens.collection}
                // A press in a card, or its page taking the keys, focuses it, and the event goes on to the page.
                onPointerDownCapture={() => interactive && onFocus(tabId, false)}
                onFocusCapture={() => interactive && onFocus(tabId, false)}
                onPointerEnter={() => interactive && onFocus(tabId, true)}
              >
                {renderCard(tabId, { focused, transition })}
              </motion.div>
            );
          })();
          if (index === 0) return [column];
          const before = slots[index - 1];
          // A gesture in flight has no dividers: the pointer is the gesture's.
          const divider = before.kind === "member" && slot.kind === "member" && placeholder === null ? before.member : null;
          return [
            <Divider key={`divider-${slotKey(before)}`} index={divider ?? 0} interactive={interactive && !held && divider !== null}
              shows={divider !== null} shares={shares} transition={transition}
              resize={(delta, baseline) => {
                if (divider === null) return;
                const width = row.current?.clientWidth ?? 0;
                setDragged(sharesAfterResize(baseline, divider, delta, width));
              }}
              commit={(next) => {
                if (!cards.groupId || !sharesDiffer(next, cards.shares)) {
                  setDragged(null);
                  return;
                }
                void onResize(next).finally(() => setDragged(null));
              }} />,
            column,
          ];
        })}
      </AnimatePresence>
      {children}
    </div>
  );
}

/**
 * BrowserSplitCardResizeHandle: the gap between two cards, which overhangs
 * each by a little so it is comfortable to take without covering either,
 * with a capsule that stays visible at rest. A drag measures the pointer's
 * whole travel from where it began, and arrow keys step it as a complete
 * resize each.
 */
function Divider({ ref, index, interactive, shows, shares, transition, resize, commit }: {
  /** The row's presence keeps a leaving divider where it was by it. */
  ref?: Ref<HTMLDivElement>;
  index: number;
  interactive: boolean;
  /** Whether the gap carries a divider, which none does while a gesture is in flight. */
  shows: boolean;
  shares: readonly number[];
  transition: Transition;
  resize: (delta: number, baseline: readonly number[]) => void;
  commit: (shares: readonly number[]) => void;
}) {
  // Releasing lets go of the pointer and of the pages, which the drag resizes each move.
  const drag = useRef<{ pointerId: number; x: number; baseline: readonly number[]; release: () => void } | null>(null);
  const [active, setActive] = useState(false);
  const latest = useRef(shares);
  latest.current = shares;
  const finish = () => {
    const begun = drag.current;
    if (!begun) return;
    drag.current = null;
    setActive(false);
    begun.release();
    commit(latest.current);
  };
  useEffect(() => () => drag.current?.release(), []);
  return (
    <motion.div
      ref={ref}
      className="split-divider"
      layout="position"
      transition={transition}
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
    >
      {shows && <div
        className={`split-divider-handle${active ? " active" : ""}`}
        style={{ width: splitMetrics.handleHitWidth, left: (splitMetrics.gap - splitMetrics.handleHitWidth) / 2 }}
        role="separator"
        aria-orientation="vertical"
        aria-label="Resize Split View Columns"
        aria-valuetext={`Divider ${index + 1}`}
        tabIndex={interactive ? 0 : -1}
        onPointerDown={(event) => {
          if (!interactive || event.button !== 0 || drag.current) return;
          event.preventDefault();
          event.stopPropagation();
          event.currentTarget.setPointerCapture(event.pointerId);
          const pointer = holdPointer();
          const pages = holdLiveResize();
          drag.current = {
            pointerId: event.pointerId, x: event.clientX, baseline: shares,
            release: () => {
              pointer();
              pages();
            },
          };
          setActive(true);
        }}
        onPointerMove={(event) => {
          const begun = drag.current;
          if (begun && event.pointerId === begun.pointerId) resize(event.clientX - begun.x, begun.baseline);
        }}
        onPointerUp={finish}
        onPointerCancel={finish}
        onLostPointerCapture={finish}
        onKeyDown={(event) => {
          const step = event.key === "ArrowRight" ? splitMetrics.keyboardStep : event.key === "ArrowLeft" ? -splitMetrics.keyboardStep : 0;
          if (!interactive || step === 0) return;
          event.preventDefault();
          resize(step, shares);
          // Each step is its own resize, measured from the row on screen.
          requestAnimationFrame(() => commit(latest.current));
        }}
      >
        <span className="split-divider-indicator" aria-hidden />
      </div>}
    </motion.div>
  );
}
