import {
  CanSend,
  DropAroundTab,
  DropIntoList,
  DropIntoSplit,
  DropOnSpace,
  type DropTargetList,
  DropTargets,
  type Intent,
  messageOfRejection,
  type SelectedTabs,
  SelectionPreview,
  TabPlacement,
  type TabSelection,
} from "@crest/contracts";
import { CoreRejection } from "@crest/core-client";
import { useCallback, useEffect, useRef, useState } from "react";

import type { Session } from "../boot";
import { failureNotice, notices } from "../notices";
import { holdPointer } from "./pointer-hold";
import { splitDrop, splitInsertionIndex } from "./split-drop";

/**
 * What a lift carries: a tab, with a split or not, or a folder with
 * everything in it; or, when the row pressed is in the window's selection,
 * every pick of the selection, in sidebar order.
 */
export type LiftItem = {
  readonly kind: "tab" | "folder";
  readonly id: string;
  readonly carried?: { readonly tabIds: readonly string[]; readonly folderIds: readonly string[] };
};

/** What a lift that carried the selection did where it landed, for the selection to follow it. */
export interface Landing {
  /** Whether the drop moved the selection to another Space. */
  readonly leftSpace: boolean;
  readonly selected: SelectedTabs;
  /** Each copy the drop made, by its source. */
  readonly copies: ReadonlyMap<string, string>;
}

/** What the sidebar's selection does when a lift begins or lands. */
export interface LiftSelection {
  /** Lets go of pinned tabs a lift would carry with other picks, which move apart. */
  readonly releasePins: (tabIds: readonly string[]) => void;
  readonly landed: (landing: Landing) => void;
}

/**
 * Where a lift would land, as the Mac's BrowserSidebarReorderTarget: between
 * the rows of a list, inside a collapsed folder, around a current tab as a new
 * folder, on another Space, or among the cards the window shows as a split.
 * `gapBefore` names the row the insertion line stands above, or null for the
 * list's end.
 */
export type DropAim =
  | {
    readonly kind: "list";
    readonly section: TabPlacement;
    readonly folderId: string | null;
    readonly beforeTabId: string | null;
    readonly beforeFolderId: string | null;
    readonly gapBefore: string | null;
  }
  | { readonly kind: "folder"; readonly folderId: string; readonly section: TabPlacement }
  | { readonly kind: "aroundTab"; readonly tabId: string }
  | { readonly kind: "space"; readonly spaceId: string }
  | { readonly kind: "split"; readonly targetTabId: string; readonly index: number };

/** A lift in progress, as the sidebar draws it. */
export interface Lift {
  readonly item: LiftItem;
  /** The lifted row's size and where the pointer grabbed it. */
  readonly width: number;
  readonly height: number;
  readonly grab: { readonly x: number; readonly y: number };
  readonly pointer: { readonly x: number; readonly y: number };
  readonly aim: DropAim | null;
  /** Why the aimed drop, or the lift itself, is refused, or null. */
  readonly refusal: string | null;
}

/** How far the pointer travels before a press becomes a lift, as on the Mac. */
const liftDistance = 4;
/** How long a row ignores activation after a drop, so the drop's release does not also select it. */
const activationQuiet = 250;
/** The bands at the list's top and bottom that scroll it, and how fast at their edge. */
const scrollBand = 56;
const scrollStep = 14;
/** How far below or above a list the pointer may stray and still append to it. */
const overshoot = 160;
/** What a refused drop says when its rule says nothing of its own. */
const unplaceable = "These items cannot be placed here. Choose another destination.";

let quietUntil = 0;

/** Whether a row should ignore a click now: the release of a drop that just landed. */
export function droppedJustNow(): boolean {
  return performance.now() < quietUntil;
}

/**
 * Lifts sidebar rows and drops them where the core takes them, as the Mac's
 * reorder lift does: a press that travels lifts the row, the core says once
 * where the lift may go (`DropTargets`), each place the pointer aims at is
 * checked as it reaches it (`CanSend`), and releasing sends that one drop.
 * Escape, a context menu or releasing with nothing aimed at puts it back.
 */
export function useSidebarLift(session: Session, spaceId: string, selectionFollows: LiftSelection) {
  const [lift, setLift] = useState<Lift | null>(null);
  const current = useRef<Lift | null>(null);
  const plan = useRef<{ selected: SelectedTabs; targets: DropTargetList } | null>(null);
  const follows = useRef(selectionFollows);
  follows.current = selectionFollows;
  const checked = useRef(new Map<string, string | null | Promise<void>>());
  const cleanup = useRef<(() => void) | null>(null);

  const update = useCallback((next: Lift | null) => {
    current.current = next;
    setLift(next);
    // The page row draws the column a split drop would take.
    splitDrop.set(next?.aim?.kind === "split" && !next.refusal ? next.aim.index : null);
  }, []);

  const end = useCallback(() => {
    cleanup.current?.();
    cleanup.current = null;
    plan.current = null;
    checked.current.clear();
    update(null);
  }, [update]);

  useEffect(() => end, [end, spaceId]);

  const intentFor = useCallback((aim: DropAim, selection: TabSelection): Intent => {
    const { workspaceId, windowId } = session;
    switch (aim.kind) {
      case "list":
        return DropIntoList({
          workspaceId, windowId, spaceId, selection, section: aim.section, folderId: aim.folderId,
          beforeTabId: aim.beforeTabId, beforeFolderId: aim.beforeFolderId,
        });
      case "folder":
        return DropIntoList({
          workspaceId, windowId, spaceId, selection, section: aim.section, folderId: aim.folderId, beforeTabId: null,
          beforeFolderId: null,
        });
      case "aroundTab":
        return DropAroundTab({ workspaceId, windowId, spaceId, selection, tabId: aim.tabId, title: "New Folder" });
      case "space":
        return DropOnSpace({ workspaceId, windowId, spaceId, selection, destinationSpaceId: aim.spaceId });
      case "split":
        return DropIntoSplit({ workspaceId, windowId, spaceId, selection, targetTabId: aim.targetTabId, index: aim.index });
    }
  }, [session, spaceId]);

  /** Aims at what is under the pointer, and asks the core once whether that drop lands. */
  const aimAt = useCallback((x: number, y: number) => {
    const lifted = current.current;
    if (!lifted) return;
    const planned = plan.current;
    const aim = planned ? aimUnder(x, y, lifted.item, planned.targets) : null;
    let refusal: string | null = planned?.targets.refusal ? messageOfRejection(planned.targets.refusal) ?? unplaceable : null;
    // The page area says at once whether the lift joins its cards.
    const splitRefusal = aim?.kind === "split" ? planned?.targets.split?.refusal ?? null : null;
    if (splitRefusal && !refusal) refusal = messageOfRejection(splitRefusal) ?? unplaceable;
    if (aim && aim.kind !== "split" && planned && !refusal) {
      const key = JSON.stringify(aim);
      const known = checked.current.get(key);
      if (typeof known === "string" || known === null) refusal = known;
      else if (known === undefined) {
        checked.current.set(key, session.core.query(CanSend({ intent: intentFor(aim, planned.selected.selection) })).then(
          (answer) => {
            checked.current.set(key, answer.refusal ? messageOfRejection(answer.refusal) ?? unplaceable : null);
            const now = current.current;
            if (now) aimAt(now.pointer.x, now.pointer.y);
          },
          () => void checked.current.set(key, unplaceable),
        ));
      }
    }
    update({ ...lifted, pointer: { x, y }, aim, refusal });
  }, [session, intentFor, update]);

  const drop = useCallback(async () => {
    const lifted = current.current;
    const planned = plan.current;
    end();
    if (!lifted?.aim || !planned || lifted.refusal) return;
    quietUntil = performance.now() + activationQuiet;
    try {
      const changes = await session.core.send(intentFor(lifted.aim, planned.selected.selection));
      // A lifted selection stays selected where it landed, its copies in
      // place of the tabs that stayed behind; one that left the Space is let go.
      if (lifted.item.carried) {
        const copies = new Map(changes.flatMap((change) =>
          change.$kind === "TabCopied" && change.workspaceId === session.workspaceId
            ? [[change.sourceTabId, change.copyTabId] as const] : []));
        follows.current.landed({ leftSpace: lifted.aim.kind === "space", selected: planned.selected, copies });
      }
    } catch (error) {
      if (!(error instanceof CoreRejection)) throw error;
      notices.post(failureNotice(messageOfRejection(error.rejection) ?? unplaceable));
    }
  }, [session, intentFor, end]);

  /** Watches a press on a row, which lifts it once the pointer travels. */
  const press = useCallback((item: LiftItem, event: React.PointerEvent<HTMLElement>) => {
    if (event.button !== 0 || current.current) return;
    const element = event.currentTarget;
    const start = { x: event.clientX, y: event.clientY };
    const pointerId = event.pointerId;
    let lifted = false;
    let scrolling = 0;
    // A lift holds the pointer, so a page under it does not take its events.
    let letGo: (() => void) | null = null;

    const scroll = () => {
      const now = current.current;
      const list = document.querySelector<HTMLElement>(".tab-list");
      if (!now || !list) return;
      const bounds = list.getBoundingClientRect();
      const top = scrollBand - (now.pointer.y - bounds.top);
      const bottom = scrollBand - (bounds.bottom - now.pointer.y);
      const depth = Math.max(top, bottom) / scrollBand;
      if (depth > 0 && now.pointer.x >= bounds.left && now.pointer.x <= bounds.right) {
        list.scrollTop += (top > bottom ? -1 : 1) * scrollStep * Math.min(depth, 1);
        aimAt(now.pointer.x, now.pointer.y);
      }
      scrolling = requestAnimationFrame(scroll);
    };

    const begin = async (x: number, y: number) => {
      lifted = true;
      letGo = holdPointer();
      element.setPointerCapture(pointerId);
      const bounds = element.getBoundingClientRect();
      update({
        item, width: bounds.width, height: bounds.height, grab: { x: start.x - bounds.left, y: start.y - bounds.top },
        pointer: { x, y }, aim: null, refusal: null,
      });
      scrolling = requestAnimationFrame(scroll);
      const { workspaceId, windowId } = session;
      const previewOf = (tabIds: readonly string[], folderIds: readonly string[]) =>
        session.core.query(SelectionPreview({ workspaceId, spaceId, tabIds, folderIds }));
      try {
        const carried = item.carried;
        let preview = carried
          ? await previewOf(carried.tabIds, carried.folderIds)
          : await previewOf(item.kind === "tab" ? [item.id] : [], item.kind === "folder" ? [item.id] : []);
        // Pinned tabs a selection would carry with other picks move apart, so
        // the selection lets them go; a press on one of them lifts nothing.
        const pins = preview.members.filter((member) => member.placement === TabPlacement.pinned).map((member) => member.id);
        if (carried && pins.length > 0 && (pins.length < preview.members.length || preview.folderIds.length > 0)) {
          follows.current.releasePins(pins);
          if (item.kind === "tab" && pins.includes(item.id)) {
            end();
            return;
          }
          const tabIds = carried.tabIds.filter((id) => !pins.includes(id));
          preview = await previewOf(tabIds, carried.folderIds);
          if (current.current) update({ ...current.current, item: { ...item, carried: { tabIds, folderIds: carried.folderIds } } });
        }
        const targets = await session.core.query(DropTargets({ workspaceId, windowId, spaceId, selection: preview.selection }));
        if (!current.current) return;
        plan.current = { selected: preview, targets };
        aimAt(current.current.pointer.x, current.current.pointer.y);
      } catch {
        end();
      }
    };

    const move = (moved: PointerEvent) => {
      if (moved.pointerId !== pointerId) return;
      if (!lifted) {
        if (Math.hypot(moved.clientX - start.x, moved.clientY - start.y) >= liftDistance) void begin(moved.clientX, moved.clientY);
        return;
      }
      aimAt(moved.clientX, moved.clientY);
    };
    const release = (released: PointerEvent) => {
      if (released.pointerId !== pointerId) return;
      if (lifted) void drop();
      else stop();
    };
    const key = (pressed: KeyboardEvent) => {
      if (pressed.key === "Escape" && lifted) {
        pressed.preventDefault();
        end();
      }
    };
    const stop = () => {
      letGo?.();
      letGo = null;
      cancelAnimationFrame(scrolling);
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", release);
      window.removeEventListener("pointercancel", cancel);
      window.removeEventListener("keydown", key, true);
      window.removeEventListener("contextmenu", cancel, true);
    };
    const cancel = () => end();
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", release);
    window.addEventListener("pointercancel", cancel);
    window.addEventListener("keydown", key, true);
    window.addEventListener("contextmenu", cancel, true);
    cleanup.current = stop;
  }, [session, spaceId, aimAt, drop, end, update]);

  return { lift, press };
}

/**
 * What the sidebar under (`x`, `y`) offers the lift, most specific first, as
 * the Mac ranks its zones: another Space, a collapsed folder's or a current
 * tab's middle half, then the list the pointer is in, or one it strayed just
 * past.
 */
function aimUnder(x: number, y: number, item: LiftItem, targets: DropTargetList): DropAim | null {
  // Over the page area, the lift joins the shown cards as a split, at the
  // slot the pointer has passed, where the core offers it.
  const slot = splitInsertionIndex(x, y);
  if (slot !== null) return targets.split ? { kind: "split", targetTabId: targets.split.tabId, index: slot } : null;
  const under = document.elementsFromPoint(x, y);
  const find = (selector: string) => under.map((element) => element.closest<HTMLElement>(selector)).find((element) => element) ?? null;
  const middle = (element: HTMLElement) => {
    const bounds = element.getBoundingClientRect();
    return y >= bounds.top + bounds.height / 4 && y <= bounds.bottom - bounds.height / 4;
  };
  // What the lift carries is no place to drop it.
  const carriesFolder = (id: string) => (item.carried ? item.carried.folderIds.includes(id) : item.kind === "folder" && item.id === id);
  const carriesTab = (id: string) => (item.carried ? item.carried.tabIds.includes(id) : item.kind === "tab" && item.id === id);

  const space = find("[data-space]");
  if (space && targets.spaceIds.includes(space.dataset.space!)) return { kind: "space", spaceId: space.dataset.space! };

  const folder = find("[data-folder]");
  if (folder && folder.dataset.collapsed === "true" && middle(folder) && !carriesFolder(folder.dataset.folder!)) {
    const section = TabPlacement.named(folder.dataset.location)!;
    return { kind: "folder", folderId: folder.dataset.folder!, section };
  }

  const tab = find("[data-around-tab]");
  if (tab && middle(tab) && targets.folderAroundTabIds.includes(tab.dataset.aroundTab!) && !carriesTab(tab.dataset.aroundTab!)) {
    return { kind: "aroundTab", tabId: tab.dataset.aroundTab! };
  }

  let list = find("[data-list-section]");
  if (!list) {
    // A pointer that strays past a list's top or bottom still reaches it.
    const lists = [...document.querySelectorAll<HTMLElement>("[data-list-section]")];
    let nearest: { element: HTMLElement; distance: number } | null = null;
    for (const candidate of lists) {
      const bounds = candidate.getBoundingClientRect();
      if (x < bounds.left - 24 || x > bounds.right + 24) continue;
      const distance = y < bounds.top ? bounds.top - y : y > bounds.bottom ? y - bounds.bottom : 0;
      if (distance <= overshoot && (!nearest || distance < nearest.distance)) nearest = { element: candidate, distance };
    }
    list = nearest?.element ?? null;
  }
  if (!list) return null;
  const section = TabPlacement.named(list.dataset.listSection)!;
  const folderId = list.dataset.listFolder || null;
  if (!targets.lists.some((target) => target.section === section && target.folderId === folderId)) return null;

  const rows = [...list.querySelectorAll<HTMLElement>(":scope > [data-row]")].filter((row) => row.offsetParent !== null);
  const grid = list.classList.contains("pinned-grid");
  const before = rows.find((row) => {
    const bounds = row.getBoundingClientRect();
    if (!grid) return y < bounds.top + bounds.height / 2;
    // The grid reads by lines: an earlier line, or this line left of the tile's middle.
    return y < bounds.top || (y <= bounds.bottom && x < bounds.left + bounds.width / 2);
  }) ?? null;
  return {
    kind: "list", section, folderId,
    beforeTabId: before?.dataset.beforeTab ?? null,
    beforeFolderId: before?.dataset.beforeFolder ?? null,
    gapBefore: before?.dataset.row ?? null,
  };
}
