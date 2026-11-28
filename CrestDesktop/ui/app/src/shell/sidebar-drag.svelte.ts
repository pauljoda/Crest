import { sidebarSpacing } from "../appearance.svelte";
import {
  CanSend,
  DropAroundTab,
  DropIntoList,
  DropIntoSplit,
  DropOnSpace,
  type DropTargetList,
  DropTargets,
  type SessionIntent,
  messageOfRejection,
  type SelectedTabs,
  SelectionPreview,
  TabPlacement,
  type TabSelection,
} from "@crest/contracts";
import { CoreRejection } from "@crest/core-client";
import { tick, untrack } from "svelte";

import type { Session } from "../boot";
import { reducesMotion } from "../motion";
import { failureNotice, notices } from "../notices";
import { holdPointer } from "./pointer-hold";
import { inOtherSpace } from "./sidebar-selection";
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
  /** How much room the lift makes where it would land: its rows' slots together, as the Mac's batch height. */
  readonly room: number;
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

// MARK: - Room for a lift

/** What moves in a sidebar's list: each row, split card and divider, whichever stands outermost. */
export const movingRows = ".sidebar-row, .split-card, .current-tabs-divider, .practice-saved-caption";

/**
 * Where each outermost moving element of `page` is laid out, by its offsets:
 * scrolling the list moves none of them, and nor does the shift a lift makes
 * room with. One a lift hid stands nowhere.
 */
export function layoutOf(page: Element | null | undefined): Map<HTMLElement, { readonly left: number; readonly top: number }> {
  const laid = new Map<HTMLElement, { left: number; top: number }>();
  for (const element of page?.querySelectorAll<HTMLElement>(movingRows) ?? []) {
    if (element.offsetParent === null || element.parentElement?.closest(movingRows)) continue;
    laid.set(element, { left: element.offsetLeft, top: element.offsetTop });
  }
  return laid;
}

/** Where each outermost moving element of `page` is drawn now: its layout and its shift, as far as the shift has eased. */
function drawnOf(page: Element | null | undefined): Map<HTMLElement, { readonly left: number; readonly top: number }> {
  const drawn = new Map<HTMLElement, { left: number; top: number }>();
  for (const [element, at] of layoutOf(page)) drawn.set(element, { left: at.left, top: at.top + easedShift(element) });
  return drawn;
}

/** How far `element` is drawn from its layout now by its translate, eased as far as it has. */
function easedShift(element: Element): number {
  const translate = getComputedStyle(element).translate;
  if (!translate || translate === "none") return 0;
  return Number.parseFloat(translate.split(" ")[1] ?? "0") || 0;
}

/** How far `element`, or the row it is in, is drawn from where it rests, as far as its shift has eased. */
function shiftOf(element: Element): number {
  for (let node: Element | null = element; node; node = node.parentElement) {
    if (!node.matches(movingRows)) continue;
    const shift = easedShift(node);
    if (shift) return shift;
  }
  return 0;
}

/** Where `element` rests, the room a lift made taken back out. */
function resting(element: Element): DOMRect {
  const box = element.getBoundingClientRect();
  const shift = shiftOf(element);
  return shift ? new DOMRect(box.x, box.y - shift, box.width, box.height) : box;
}

/**
 * The room a lift makes: the lifted row's slot, or, for a lifted selection,
 * every carried row's slot together, each a row and the list's 2px gap, as
 * the Mac's batch height adds its rows up. A carried folder brings its
 * contents' height with it.
 */
function roomFor(item: LiftItem, page: Element | null | undefined, height: number): number {
  if (!page) return height + 2;
  const folderSlot = (id: string) => {
    const row = page.querySelector<HTMLElement>(`[data-folder="${id}"]`);
    if (!row || row.offsetParent === null) return 0;
    const contents = page.querySelector<HTMLElement>(`[data-list-folder="${id}"]`);
    return row.offsetHeight + 2 + (contents && contents.offsetHeight > 0 ? contents.offsetHeight + 2 : 0);
  };
  const carried = item.carried;
  if (!carried) return item.kind === "folder" ? folderSlot(item.id) || height + 2 : height + 2;
  let room = 0;
  for (const id of carried.tabIds) {
    const row = page.querySelector<HTMLElement>(`[data-row="${id}"], [data-before-tab="${id}"]`);
    if (row && row.offsetParent !== null && !row.closest(".pinned-grid")) room += row.offsetHeight + 2 * sidebarSpacing.current;
  }
  for (const id of carried.folderIds) room += folderSlot(id);
  return room || height + 2;
}

/** Shifts `element` down by `room`, or back, easing as the stylesheet's transition does unless `instant`. */
function shift(element: HTMLElement, room: number, instant: boolean) {
  const value = room ? `0px ${room}px` : "";
  if (instant || reducesMotion()) {
    // Applied even when unchanged, which stops any easing still under way.
    element.style.transition = "none";
    element.style.translate = value;
    void element.offsetHeight;
    element.style.transition = "";
  } else if (element.style.translate !== value) {
    element.style.translate = value;
  }
}

/** Whether a row should ignore a click now: the release of a drop that just landed. */
export function droppedJustNow(): boolean {
  return performance.now() < quietUntil;
}

/** A lift in a sidebar, as `useSidebarLift` answers it. */
export interface SidebarLift {
  /** The lift in progress, or null; read in a reactive expression, it follows the lift. */
  readonly lift: Lift | null;
  /** Watches a press on a row, which lifts it once the pointer travels. */
  readonly press: (item: LiftItem, event: PointerEvent & { currentTarget: HTMLElement }) => void;
}

/**
 * Lifts sidebar rows and drops them where the core takes them, as the Mac's
 * reorder lift does: a press that travels lifts the row, the core says once
 * where the lift may go (`DropTargets`), each place the pointer aims at is
 * checked as it reaches it (`CanSend`), and releasing sends that one drop.
 * Escape, a context menu or releasing with nothing aimed at puts it back.
 * Call during a component's initialization.
 */
export function useSidebarLift(session: Session, spaceId: () => string, selectionFollows: () => LiftSelection): SidebarLift {
  let lift = $state.raw<Lift | null>(null);
  let current: Lift | null = null;
  let plan: { selected: SelectedTabs; targets: DropTargetList } | null = null;
  // Which lift the core's answers belong to: it advances as a lift begins or
  // ends, so an answer that arrives for an earlier one changes nothing.
  let gesture = 0;
  // Whether the pointer let go of the lift before the core said where it may land.
  let releasedEarly = false;
  const checked = new Map<string, string | null | Promise<void>>();
  let cleanup: (() => void) | null = null;
  // The sidebar the lift started in, which alone it aims into, and the
  // Getting Started practice window holding it, whose cards it joins in
  // place of the window's.
  let scope: { sidebar: HTMLElement | null; practice: HTMLElement | null } = { sidebar: null, practice: null };
  // What makes room for the lift now.
  let roomy: HTMLElement[] = [];

  /** The page of the lift's sidebar the window shows. */
  const shownPage = () => scope.sidebar?.querySelector(".space-page:not([aria-hidden])") ?? scope.sidebar;

  /**
   * The room the Mac's reorder layout makes (BrowserSidebarReorderLayout):
   * aimed between a list's rows, everything from the aimed row down moves
   * aside by the lifted row's slot, on dragSource, so the lift shows where it
   * lands; elsewhere, or refused, the room closes. The lifted row's own slot
   * has closed already. Aiming reads the rows where they rest.
   */
  const makeRoom = (next: Lift | null, instant = false) => {
    const page = shownPage();
    const room = new Map<HTMLElement, number>();
    const aim = next?.aim;
    if (next && aim?.kind === "list" && !next.refusal && page) {
      const list = [...page.querySelectorAll<HTMLElement>("[data-list-section]")]
        .find((element) => element.dataset.listSection === aim.section.name && (element.dataset.listFolder || null) === aim.folderId);
      if (list && !list.classList.contains("pinned-grid")) {
        const rows = [...list.querySelectorAll<HTMLElement>(":scope > [data-row]")].filter((row) => row.offsetParent !== null);
        const anchor = aim.gapBefore ? rows.find((row) => row.dataset.row === aim.gapBefore) ?? null : null;
        const last = rows.at(-1);
        const top = anchor ? anchor.offsetTop : last ? last.offsetTop + last.offsetHeight + 1 : list.offsetTop;
        for (const [element, at] of layoutOf(page)) if (at.top >= top - 0.5) room.set(element, next.room);
      }
    }
    for (const element of roomy) if (!room.has(element)) shift(element, 0, instant);
    for (const [element, slot] of room) shift(element, slot, instant);
    roomy = [...room.keys()];
  };

  /**
   * Keeps every row drawn where it was before the lift's slot closed or came
   * back, then lets the room ease each to where it now belongs, so closing,
   * opening and putting back are one motion.
   */
  const easeFrom = (before: ReadonlyMap<HTMLElement, { readonly left: number; readonly top: number }>, next: Lift | null) => {
    const page = shownPage();
    const held = new Set(roomy);
    for (const [element, at] of layoutOf(page)) {
      const from = before.get(element);
      if (!from) continue;
      // Pinned where it was drawn, which also stops any easing still under way.
      shift(element, Math.abs(from.top - at.top) < 0.5 ? 0 : from.top - at.top, true);
      held.add(element);
    }
    roomy = [...held];
    makeRoom(next);
  };

  // The room follows the lift's aim as it draws; ending the lift lets go of the room itself.
  $effect(() => {
    const next = lift;
    if (next) untrack(() => makeRoom(next));
  });

  const update = (next: Lift | null) => {
    current = next;
    lift = next;
    // The page row draws the column a split drop would take.
    splitDrop.set(next?.aim?.kind === "split" && !next.refusal ? next.aim.index : null, session.windowId);
  };

  const end = () => {
    cleanup?.();
    cleanup = null;
    gesture++;
    releasedEarly = false;
    plan = null;
    checked.clear();
    makeRoom(null, true);
    update(null);
  };

  /** Puts the lift back: the lifted row returns to its slot and the rows around it move back, as the Mac's do. */
  const putBack = async () => {
    const before = drawnOf(shownPage());
    cleanup?.();
    cleanup = null;
    gesture++;
    releasedEarly = false;
    plan = null;
    checked.clear();
    update(null);
    await tick();
    easeFrom(before, null);
  };

  // A lift ends with the Space it started in, and with the sidebar.
  $effect(() => {
    spaceId();
    return end;
  });

  const intentFor = (aim: DropAim, selection: TabSelection): SessionIntent => {
    const { workspaceId, windowId } = session;
    const space = spaceId();
    switch (aim.kind) {
      case "list":
        return DropIntoList({
          workspaceId, windowId, spaceId: space, selection, section: aim.section, folderId: aim.folderId,
          beforeTabId: aim.beforeTabId, beforeFolderId: aim.beforeFolderId,
        });
      case "folder":
        return DropIntoList({
          workspaceId, windowId, spaceId: space, selection, section: aim.section, folderId: aim.folderId, beforeTabId: null,
          beforeFolderId: null,
        });
      case "aroundTab":
        return DropAroundTab({ workspaceId, windowId, spaceId: space, selection, tabId: aim.tabId, title: "New Folder" });
      case "space":
        return DropOnSpace({ workspaceId, windowId, spaceId: space, selection, destinationSpaceId: aim.spaceId });
      case "split":
        return DropIntoSplit({ workspaceId, windowId, spaceId: space, selection, targetTabId: aim.targetTabId, index: aim.index });
    }
  };

  /** Aims at what is under the pointer, and asks the core once whether that drop lands. */
  const aimAt = (x: number, y: number) => {
    const lifted = current;
    if (!lifted) return;
    const planned = plan;
    const aim = planned ? aimUnder(x, y, lifted.item, planned.targets, scope) : null;
    let refusal: string | null = planned?.targets.refusal ? messageOfRejection(planned.targets.refusal) ?? unplaceable : null;
    // The page area says at once whether the lift joins its cards.
    const splitRefusal = aim?.kind === "split" ? planned?.targets.split?.refusal ?? null : null;
    if (splitRefusal && !refusal) refusal = messageOfRejection(splitRefusal) ?? unplaceable;
    if (aim && aim.kind !== "split" && planned && !refusal) {
      const key = JSON.stringify(aim);
      const known = checked.get(key);
      if (typeof known === "string" || known === null) refusal = known;
      else if (known === undefined) {
        const asked = gesture;
        checked.set(key, session.core.query(CanSend({ intent: intentFor(aim, planned.selected.selection) })).then(
          (answer) => {
            if (gesture !== asked) return;
            checked.set(key, answer.refusal ? messageOfRejection(answer.refusal) ?? unplaceable : null);
            const now = current;
            if (now) aimAt(now.pointer.x, now.pointer.y);
          },
          () => {
            if (gesture === asked) checked.set(key, unplaceable);
          },
        ));
      }
    }
    update({ ...lifted, pointer: { x, y }, aim, refusal });
  };

  const drop = async () => {
    const lifted = current;
    const planned = plan;
    // A release before the core said where the lift may go lands once it has.
    if (lifted && !planned) {
      releasedEarly = true;
      cleanup?.();
      cleanup = null;
      return;
    }
    if (!lifted?.aim || !planned || lifted.refusal) return void putBack();
    quietUntil = performance.now() + activationQuiet;
    // The lift holds its room until the drop's change has drawn the rows where the room was.
    cleanup?.();
    cleanup = null;
    const own = gesture;
    let landed = false;
    try {
      const changes = await session.core.send(intentFor(lifted.aim, planned.selected.selection));
      landed = true;
      // A lifted selection stays selected where it landed, its copies in
      // place of the tabs that stayed behind; one that left the Space is let go.
      // A lift that ended meanwhile, with its Space, leaves the selection alone.
      if (lifted.item.carried && gesture === own) {
        const copies = new Map(changes.flatMap((change) =>
          change.$kind === "TabCopied" && change.workspaceId === session.workspaceId
            ? [[change.sourceTabId, change.copyTabId] as const] : []));
        selectionFollows().landed({ leftSpace: lifted.aim.kind === "space", selected: planned.selected, copies });
      }
    } catch (error) {
      if (!(error instanceof CoreRejection)) throw error;
      notices.post(failureNotice(messageOfRejection(error.rejection) ?? unplaceable));
    } finally {
      if (landed) {
        await tick();
        if (gesture === own) end();
      } else if (gesture === own) {
        void putBack();
      }
    }
  };

  /** Watches a press on a row, which lifts it once the pointer travels. */
  const press = (item: LiftItem, event: PointerEvent & { currentTarget: HTMLElement }) => {
    if (event.button !== 0 || current) return;
    const element = event.currentTarget;
    const start = { x: event.clientX, y: event.clientY };
    const pointerId = event.pointerId;
    // The Space the press began in, which the lift's questions name.
    const space = spaceId();
    let lifted = false;
    let scrolling = 0;
    // A lift holds the pointer, so a page under it does not take its events.
    let letGo: (() => void) | null = null;

    const scroll = () => {
      const now = current;
      const list = [...(scope.sidebar ?? document).querySelectorAll<HTMLElement>(".tab-list")].find((element) => !inOtherSpace(element));
      if (!now || !list) return;
      const bounds = list.getBoundingClientRect();
      const top = scrollBand - (now.pointer.y - bounds.top);
      const bottom = scrollBand - (bounds.bottom - now.pointer.y);
      const depth = Math.max(top, bottom) / scrollBand;
      // Only inside the list, as the Mac's: past it, the pinned tiles or other chrome own the drop.
      const inside = now.pointer.x >= bounds.left && now.pointer.x <= bounds.right
        && now.pointer.y >= bounds.top && now.pointer.y <= bounds.bottom;
      if (depth > 0 && inside) {
        list.scrollTop += (top > bottom ? -1 : 1) * scrollStep * Math.min(depth, 1);
        aimAt(now.pointer.x, now.pointer.y);
      }
      scrolling = requestAnimationFrame(scroll);
    };

    const begin = async (x: number, y: number) => {
      lifted = true;
      const own = ++gesture;
      releasedEarly = false;
      scope = { sidebar: element.closest<HTMLElement>(".sidebar"), practice: element.closest<HTMLElement>("[data-practice-window]") };
      letGo = holdPointer();
      element.setPointerCapture(pointerId);
      const bounds = element.getBoundingClientRect();
      // The lifted row's slot closes as it rises, the rows under it moving up.
      const before = drawnOf(shownPage());
      update({
        item, width: bounds.width, height: bounds.height, grab: { x: start.x - bounds.left, y: start.y - bounds.top },
        room: roomFor(item, shownPage(), bounds.height), pointer: { x, y }, aim: null, refusal: null,
      });
      void tick().then(() => easeFrom(before, current));
      scrolling = requestAnimationFrame(scroll);
      const { workspaceId, windowId } = session;
      const previewOf = (tabIds: readonly string[], folderIds: readonly string[]) =>
        session.core.query(SelectionPreview({ workspaceId, spaceId: space, tabIds, folderIds }));
      try {
        const carried = item.carried;
        let preview = carried
          ? await previewOf(carried.tabIds, carried.folderIds)
          : await previewOf(item.kind === "tab" ? [item.id] : [], item.kind === "folder" ? [item.id] : []);
        if (gesture !== own) return;
        // Pinned tabs a selection would carry with other picks move apart, so
        // the selection lets them go; a press on one of them lifts nothing.
        const pins = preview.members.filter((member) => member.placement === TabPlacement.pinned).map((member) => member.id);
        if (carried && pins.length > 0 && (pins.length < preview.members.length || preview.folderIds.length > 0)) {
          selectionFollows().releasePins(pins);
          if (item.kind === "tab" && pins.includes(item.id)) {
            end();
            return;
          }
          const tabIds = carried.tabIds.filter((id) => !pins.includes(id));
          preview = await previewOf(tabIds, carried.folderIds);
          if (gesture !== own || !current) return;
          update({ ...current, item: { ...item, carried: { tabIds, folderIds: carried.folderIds } } });
        }
        const targets = await session.core.query(DropTargets({ workspaceId, windowId, spaceId: space, selection: preview.selection }));
        if (gesture !== own || !current) return;
        plan = { selected: preview, targets };
        aimAt(current.pointer.x, current.pointer.y);
        if (releasedEarly) void drop();
      } catch {
        if (gesture === own) end();
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
        void putBack();
      }
    };
    const stop = () => {
      letGo?.();
      letGo = null;
      cancelAnimationFrame(scrolling);
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", release);
      window.removeEventListener("pointercancel", pointerCancel);
      window.removeEventListener("keydown", key, true);
      window.removeEventListener("contextmenu", cancel, true);
    };
    const cancel = () => void putBack();
    const pointerCancel = (cancelled: PointerEvent) => {
      if (cancelled.pointerId === pointerId) cancel();
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", release);
    window.addEventListener("pointercancel", pointerCancel);
    window.addEventListener("keydown", key, true);
    window.addEventListener("contextmenu", cancel, true);
    cleanup = stop;
  };

  return {
    get lift() {
      return lift;
    },
    press,
  };
}

/**
 * What the sidebar under (`x`, `y`) offers the lift, most specific first, as
 * the Mac ranks its zones: another Space, a collapsed folder's or a current
 * tab's middle half, then the list the pointer is in, or one it strayed just
 * past.
 */
function aimUnder(x: number, y: number, item: LiftItem, targets: DropTargetList,
  scope: { sidebar: HTMLElement | null; practice: HTMLElement | null }): DropAim | null {
  // Over the page area, the lift joins the shown cards as a split, at the
  // slot the pointer has passed, where the core offers it.
  const slot = splitInsertionIndex(x, y, scope.practice);
  if (slot !== null) return targets.split ? { kind: "split", targetTabId: targets.split.tabId, index: slot } : null;
  // Only the lift's own sidebar takes it: the guide's practice sidebar and the window's are apart.
  // Rows moved aside to make room are read where they rest, so the room
  // never moves what the pointer aims at.
  const under = document.elementsFromPoint(x, y)
    .filter((element) => (!scope.sidebar || scope.sidebar.contains(element)) && !shiftOf(element));
  const find = (selector: string) => under.map((element) => element.closest<HTMLElement>(selector)).find((element) => element) ?? null;
  const restingAt = (selector: string) => [...(scope.sidebar ?? document).querySelectorAll<HTMLElement>(selector)].find((element) => {
    if (element.offsetParent === null || inOtherSpace(element)) return false;
    const bounds = resting(element);
    return x >= bounds.left && x <= bounds.right && y >= bounds.top && y <= bounds.bottom;
  }) ?? null;
  const middle = (element: HTMLElement) => {
    const bounds = resting(element);
    return y >= bounds.top + bounds.height / 4 && y <= bounds.bottom - bounds.height / 4;
  };
  // What the lift carries is no place to drop it.
  const carriesFolder = (id: string) => (item.carried ? item.carried.folderIds.includes(id) : item.kind === "folder" && item.id === id);
  const carriesTab = (id: string) => (item.carried ? item.carried.tabIds.includes(id) : item.kind === "tab" && item.id === id);

  const space = find("[data-space]");
  if (space && targets.spaceIds.includes(space.dataset.space!)) return { kind: "space", spaceId: space.dataset.space! };

  const folder = restingAt("[data-folder]");
  if (folder && folder.dataset.collapsed === "true" && middle(folder) && !carriesFolder(folder.dataset.folder!)) {
    const section = TabPlacement.named(folder.dataset.location)!;
    return { kind: "folder", folderId: folder.dataset.folder!, section };
  }

  const tab = restingAt("[data-around-tab]");
  if (tab && middle(tab) && targets.folderAroundTabIds.includes(tab.dataset.aroundTab!) && !carriesTab(tab.dataset.aroundTab!)) {
    return { kind: "aroundTab", tabId: tab.dataset.aroundTab! };
  }

  let list = find("[data-list-section]");
  if (!list) {
    // A pointer that strays past a list's top or bottom still reaches it.
    const lists = [...(scope.sidebar ?? document).querySelectorAll<HTMLElement>("[data-list-section]")].filter((element) => !inOtherSpace(element));
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
    const bounds = resting(row);
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
