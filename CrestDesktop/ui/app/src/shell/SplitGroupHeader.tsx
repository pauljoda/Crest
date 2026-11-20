import {
  type BrandColor,
  CloseTab,
  CollapseSplit,
  DissolveSplit,
  NameSplit,
  SetSplitIcon,
  type SpaceState,
  type SplitGroupState,
  SplitGroupStateTexts,
  type TabState,
  TintSplit,
} from "@crest/contracts";
import { motion as tokens } from "@crest/design";
import { AnimatePresence, motion, useAnimate } from "motion/react";
import { type MouseEvent, useEffect, useRef, useState } from "react";

import type { Session } from "../boot";
import { showContextMenu } from "../menus";
import { Symbol } from "../symbols";
import { ColorPicker, EmojiPicker, folderDefault, Popover } from "./pickers";
import { TabIcon } from "./Sidebar";
import { rowPlacement } from "./sidebar-layout";

/** BrowserSidebarSplitGroupRowMetrics.pointer: the stacked icons draw at a member favicon's size. */
const glyph = 18;

/**
 * The Mac's BrowserSidebarSplitGroupHeader: the split's own row, standing as
 * a folder's header does, with its members' icons stacked in the folder
 * symbol's column, or a chevron while it is collapsed, and its title. A click
 * opens or closes the members under it, a double click renames it, and its
 * menu, behind the trailing ellipsis and a right-click alike, names it, gives
 * it an emoji or a colour, separates its tabs or closes them.
 */
export function SplitGroupHeader({ session, space, groupId, group, members, focusedId, pagesByTab, depth, onMenu }: {
  session: Session;
  space: SpaceState;
  groupId: string;
  group: SplitGroupState | null;
  members: readonly TabState[];
  focusedId: string | null;
  pagesByTab: ReadonlyMap<string, string>;
  depth: number;
  /** The menu a right-click shows, where the window's selection holds a member: its tabs' own. */
  onMenu?: (event: MouseEvent) => boolean;
}) {
  const { workspaceId } = session;
  const spaceId = space.id;
  const title = group?.displayTitle ?? SplitGroupStateTexts.defaultTitle.text;
  const collapsed = group?.isCollapsed ?? false;
  const [renaming, setRenaming] = useState(false);
  const [choosing, setChoosing] = useState<{ kind: "icon" | "color"; anchor: DOMRect } | null>(null);
  const row = useRef<HTMLDivElement>(null);
  const send = (intent: Parameters<typeof session.core.send>[0]) => void session.core.send(intent).catch(() => {});
  // A split of open tabs closes; one the session keeps does not.
  const canClose = members.length > 0 && !members[0].placement.isDurable;

  const menu = (at: { clientX: number; clientY: number }) => void showContextMenu(session.shell, at, [
    { title: "Rename Split View…", run: () => setRenaming(true) },
    { title: "Change Icon…", run: () => row.current && setChoosing({ kind: "icon", anchor: row.current.getBoundingClientRect() }) },
    { title: "Change Color…", run: () => row.current && setChoosing({ kind: "color", anchor: row.current.getBoundingClientRect() }) },
    "separator",
    { title: "Separate All Tabs", run: () => send(DissolveSplit({ workspaceId, spaceId, groupId })) },
    ...(canClose ? ["separator" as const, {
      title: "Close Split",
      // Closing the second to last member ends the split; the last is an ordinary tab's close.
      run: () => {
        for (const member of members) send(CloseTab({ workspaceId, windowId: session.windowId, spaceId, tabId: member.id, returnTabId: null }));
      },
    }] : []),
  ]);

  const commit = (name: string | null) => {
    setRenaming(false);
    if (name === null) return;
    send(NameSplit({ workspaceId, spaceId, groupId, name: name.trim() || null }));
  };

  return (
    <div ref={row} className="sidebar-row folder-row split-header" style={rowPlacement(depth, true)}
      role="button" tabIndex={0} aria-expanded={!collapsed} aria-label={title}
      aria-description={collapsed ? "Expands this Split View" : "Collapses this Split View"}
      onClick={(event) => {
        if (renaming || event.detail > 1) return;
        send(CollapseSplit({ workspaceId, spaceId, groupId, isCollapsed: !collapsed }));
      }}
      onDoubleClick={() => setRenaming(true)}
      onAuxClick={(event) => {
        if (event.button !== 1 || !canClose) return;
        for (const member of members) send(CloseTab({ workspaceId, windowId: session.windowId, spaceId, tabId: member.id, returnTabId: null }));
      }}
      onContextMenu={(event) => {
        event.preventDefault();
        event.stopPropagation();
        if (onMenu?.(event)) return;
        menu(event);
      }}>
      <span className="split-header-icon" aria-hidden>
        <AnimatePresence initial={false} mode="popLayout">
          {collapsed ? (
            <motion.span key="chevron" className="split-chevron" initial={{ opacity: 0, rotate: 90 }} animate={{ opacity: 1, rotate: 0 }}
              exit={{ opacity: 0, rotate: 90 }} transition={tokens.disclosure}>
              <Symbol name="chevron.right" size={glyph * 0.75} strokeWidth={2.25} />
            </motion.span>
          ) : group?.displayEmojiIcon ? (
            <motion.span key="emoji" className="split-emoji" style={{ fontSize: glyph * 0.9 }} initial={{ opacity: 0 }}
              animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={tokens.disclosure}>
              {group.displayEmojiIcon}
            </motion.span>
          ) : (
            <motion.span key="deck" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={tokens.disclosure}>
              <IconDeck session={session} members={members} focusedId={focusedId} pagesByTab={pagesByTab} />
            </motion.span>
          )}
        </AnimatePresence>
      </span>
      {renaming
        ? <SplitNameField initial={title} onDone={commit} />
        : <span className="row-title split-header-title">{title}</span>}
      <button type="button" className="split-header-actions" aria-label="Split View actions" title="Split View actions"
        onClick={(event) => {
          event.stopPropagation();
          const bounds = event.currentTarget.getBoundingClientRect();
          menu({ clientX: bounds.left, clientY: bounds.bottom });
        }}>
        <Symbol name="ellipsis" size={14} />
      </button>
      <AnimatePresence>
        {choosing?.kind === "color" && (
          <Popover key="color" anchor={choosing.anchor} label="Split View Color" onClose={() => setChoosing(null)}>
            <ColorPicker title="Split View Color" color={group?.tint ?? folderDefault}
              resetTitle={group?.tint ? "Use Default Color" : null}
              onChoose={(tint: BrandColor) => send(TintSplit({ workspaceId, spaceId, groupId, tint }))}
              onReset={() => send(TintSplit({ workspaceId, spaceId, groupId, tint: null }))} />
          </Popover>
        )}
        {choosing?.kind === "icon" && (
          <Popover key="icon" anchor={choosing.anchor} label="Split View Icon" onClose={() => setChoosing(null)}>
            <EmojiPicker title="Split View Icon" current={group?.displayEmojiIcon ?? null}
              resetTitle={group?.displayEmojiIcon ? "Use Stacked Icons" : null}
              onChoose={(emoji) => {
                send(SetSplitIcon({ workspaceId, spaceId, groupId, emoji }));
                setChoosing(null);
              }}
              onReset={() => {
                send(SetSplitIcon({ workspaceId, spaceId, groupId, emoji: null }));
                setChoosing(null);
              }} />
          </Popover>
        )}
      </AnimatePresence>
    </div>
  );
}

/**
 * The members' icons stacked like cards, at most three, the focused one last
 * and on top: each further back is a little smaller, turned a little about
 * its foot, and lifted a little; the deck slides as focus moves, and the
 * focused icon hops.
 */
function IconDeck({ session, members, focusedId, pagesByTab }: {
  session: Session;
  members: readonly TabState[];
  focusedId: string | null;
  pagesByTab: ReadonlyMap<string, string>;
}) {
  const deck = deckMembers(members, focusedId);
  const front = Math.max(deck.length - 1, 0);
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  return (
    <span className="split-deck" style={{ width: glyph * 1.45, height: glyph }}>
      {deck.map((member, index) => (
        <DeckCard key={member.id} focused={member.id === focusedId} focusedId={focusedId} reduce={reduce}
          style={{
            scale: 1 - (front - index) * 0.055,
            rotate: (index - front) * 3.5,
            x: index * glyph * 0.28,
            y: (front - index) * glyph * 0.045,
            zIndex: index,
          }}>
          <TabIcon session={session} tab={member} pageId={pagesByTab.get(member.id) ?? null} size={glyph} />
        </DeckCard>
      ))}
    </span>
  );
}

function DeckCard({ focused, focusedId, reduce, style, children }: {
  focused: boolean;
  focusedId: string | null;
  reduce: boolean;
  style: { scale: number; rotate: number; x: number; y: number; zIndex: number };
  children: React.ReactNode;
}) {
  const [scope, animate] = useAnimate<HTMLSpanElement>();
  const first = useRef(true);
  // The focused icon hops as focus reaches it: up a fifth of its size and back.
  useEffect(() => {
    if (first.current) {
      first.current = false;
      return;
    }
    if (!focused || reduce || !scope.current) return;
    void animate(scope.current, { y: [0, -glyph * 0.18, 0] }, { duration: 0.22, ease: "easeInOut" });
  }, [focusedId, focused, reduce, animate, scope]);
  return (
    <motion.span className="split-deck-card" style={{ zIndex: style.zIndex, transformOrigin: "50% 100%" }}
      initial={false} animate={{ scale: style.scale, rotate: style.rotate, x: style.x, y: style.y }}
      transition={reduce ? { duration: 0 } : tokens.collection}>
      <span ref={scope} className="split-deck-face">{children}</span>
    </motion.span>
  );
}

/** BrowserSidebarSplitGroupIconDeck: the first three members, the focused one among them and last. */
function deckMembers(members: readonly TabState[], focusedId: string | null): TabState[] {
  const visible = members.slice(0, 3);
  const focused = members.find((member) => member.id === focusedId);
  if (!focused) return visible;
  if (!visible.includes(focused)) {
    if (visible.length === 0) visible.push(focused);
    else visible[visible.length - 1] = focused;
  }
  return [...visible.filter((member) => member !== focused), focused];
}

/** The split's name being edited in place: Enter or leaving keeps it, Escape cancels. */
function SplitNameField({ initial, onDone }: { initial: string; onDone: (name: string | null) => void }) {
  const field = useRef<HTMLInputElement>(null);
  const ended = useRef(false);
  const end = (name: string | null) => {
    if (ended.current) return;
    ended.current = true;
    onDone(name);
  };
  useEffect(() => {
    field.current?.focus();
    field.current?.select();
  }, []);
  return (
    <input ref={field} className="rename-field" defaultValue={initial} placeholder="Split View Name" aria-label="Split View Name"
      onClick={(event) => event.stopPropagation()}
      onKeyDown={(event) => {
        event.stopPropagation();
        if (event.key === "Enter") end(event.currentTarget.value);
        if (event.key === "Escape") end(null);
      }}
      onBlur={(event) => end(event.currentTarget.value)} />
  );
}
