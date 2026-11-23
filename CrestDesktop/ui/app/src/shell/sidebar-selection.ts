import { type SelectedTabs, SelectionPreview } from "@crest/contracts";

import type { Session } from "../boot";

/** What a person selects in the sidebar: a tab or a folder, by kind and id. */
export type SelectionItem = `tab:${string}` | `folder:${string}`;

/** What one click selects: a tab, a folder, or the members of a split. */
export type SelectionUnit = readonly SelectionItem[];

/**
 * The window's sidebar selection, as the Mac's BrowserTabMultiSelection keeps
 * it, apart from the tab whose page is shown; the core never sees it. A plain
 * click selects quietly, so a drag carries what it pressed; Ctrl or Shift
 * engages it, and only an engaged selection is drawn or acted on.
 */
export interface SidebarSelection {
  readonly items: ReadonlySet<SelectionItem>;
  /** Where a Shift range starts. */
  readonly anchor: SelectionItem | null;
  /** Where the arrow keys move from, and what Enter opens. */
  readonly focused: SelectionItem | null;
  readonly engaged: boolean;
  /** What a range adds to, kept while Shift extends the same range. */
  readonly rangeBase: ReadonlySet<SelectionItem> | null;
}

export const noSelection: SidebarSelection = { items: new Set(), anchor: null, focused: null, engaged: false, rangeBase: null };

export const tabItem = (id: string): SelectionItem => `tab:${id}`;
export const folderItem = (id: string): SelectionItem => `folder:${id}`;

/** The id an item names, and whether it is a folder. */
export function itemParts(item: SelectionItem): { readonly kind: "tab" | "folder"; readonly id: string } {
  return item.startsWith("tab:") ? { kind: "tab", id: item.slice(4) } : { kind: "folder", id: item.slice(7) };
}

/** Whether the selection holds `item` while it is engaged, as the Mac's `contains` answers. */
export function holds(selection: SidebarSelection, item: SelectionItem): boolean {
  return selection.engaged && selection.items.has(item);
}

/**
 * The units the sidebar shows, in the order it shows them: pinned tiles, the
 * saved tabs while open, then the open tabs, a folder's inside after its row
 * and the rows a collapsed folder keeps on screen, as the Mac's itemUnits
 * walks the core's outline. Each row carries its unit in `data-unit`. A
 * window's own sidebar and the Getting Started practice's each keep theirs.
 */
export function unitsShown(sidebar: HTMLElement | null): SelectionUnit[] {
  return [...(sidebar ?? document).querySelectorAll<HTMLElement>(sidebar ? "[data-unit]" : ".sidebar [data-unit]")]
    .filter((element) => element.offsetParent !== null)
    .map((element) => element.dataset.unit!.split(",") as SelectionItem[]);
}

/**
 * A click on `item`, as the Mac's `click`: Shift selects the range from the
 * anchor, or from `activeItem` when none is set, on top of what was selected
 * when Ctrl is held too; Ctrl adds or removes the unit; a plain click selects
 * the unit quietly.
 */
export function clicked(selection: SidebarSelection, item: SelectionItem, units: readonly SelectionUnit[],
  keys: { readonly command: boolean; readonly shift: boolean }, activeItem: SelectionItem | null): SidebarSelection {
  const target = units.findIndex((unit) => unit.includes(item));
  if (target < 0) return selection;
  const focused = units[target][0];
  let anchor = selection.anchor;
  let rangeBase = selection.rangeBase;
  if (keys.shift && anchor === null && activeItem) {
    const active = units.find((unit) => unit.includes(activeItem));
    // A new anchor starts a new range, never one over a base an earlier anchor left.
    if (active) {
      anchor = active[0];
      rangeBase = null;
    }
  }
  const from = anchor === null ? -1 : units.findIndex((unit) => unit.includes(anchor!));
  if (keys.shift && from >= 0) {
    const base = rangeBase ?? (keys.command ? selection.items : new Set<SelectionItem>());
    const range = units.slice(Math.min(from, target), Math.max(from, target) + 1).flat();
    return { items: new Set([...base, ...range]), anchor, focused, engaged: true, rangeBase: base };
  }
  const unit = units[target];
  let items: Set<SelectionItem>;
  if (keys.command) {
    items = new Set(selection.items);
    if (unit.every((member) => items.has(member))) for (const member of unit) items.delete(member);
    else for (const member of unit) items.add(member);
  } else {
    items = new Set(unit);
  }
  return { items, anchor: unit[0], focused, engaged: keys.command || keys.shift, rangeBase: null };
}

/** Every unit the sidebar shows, as Select All takes them. */
export function allSelected(units: readonly SelectionUnit[]): SidebarSelection {
  return {
    items: new Set(units.flat()), anchor: units[0]?.[0] ?? null, focused: units.at(-1)?.[0] ?? null, engaged: true,
    rangeBase: null,
  };
}

/**
 * Only what the sidebar still shows, and never part of a unit that changed
 * under the selection, as the Mac's `reconcile` keeps it. Answers the same
 * selection when nothing changed.
 */
export function reconciled(selection: SidebarSelection, units: readonly SelectionUnit[]): SidebarSelection {
  if (selection.items.size === 0 && selection.anchor === null && selection.focused === null) return selection;
  const available = new Set(units.flat());
  const items = new Set([...selection.items].filter((item) => available.has(item)));
  // A changed split is never partly selected after a live update.
  for (const unit of units) {
    if (unit.some((member) => items.has(member)) && !unit.every((member) => items.has(member))) {
      for (const member of unit) items.delete(member);
    }
  }
  const anchor = selection.anchor && available.has(selection.anchor) ? selection.anchor : null;
  const focused = selection.focused && available.has(selection.focused) ? selection.focused : null;
  const rangeBase = selection.rangeBase && new Set([...selection.rangeBase].filter((item) => available.has(item)));
  if (items.size === selection.items.size && anchor === selection.anchor && focused === selection.focused
    && rangeBase?.size === selection.rangeBase?.size) {
    return selection;
  }
  return { ...selection, items, anchor, focused, rangeBase };
}

/**
 * The selected items in sidebar order when the selection holds `item`, as
 * the Mac's capture finds them, or null when it does not.
 */
export function pickedWith(selection: SidebarSelection, item: SelectionItem, units: readonly SelectionUnit[]): SelectionItem[] | null {
  if (!holds(selection, item)) return null;
  const picked = units.flat().filter((candidate) => selection.items.has(candidate));
  return picked.includes(item) ? picked : null;
}

/** What `items`, picked in the Space the window shows, hold there, as the core previews it. */
export function preview(session: Session, spaceId: string, items: readonly SelectionItem[]): Promise<SelectedTabs> {
  const parts = items.map(itemParts);
  return session.core.query(SelectionPreview({
    workspaceId: session.workspaceId, spaceId,
    tabIds: parts.filter((part) => part.kind === "tab").map((part) => part.id),
    folderIds: parts.filter((part) => part.kind === "folder").map((part) => part.id),
  }));
}

/** The items a preview's picks name, a copy standing in for each source an action copied. */
export function rootItems(selected: SelectedTabs, copies: ReadonlyMap<string, string> = new Map()): SelectionUnit[] {
  return selected.roots.map((root) => [root.kind.opensList ? folderItem(root.id) : tabItem(copies.get(root.id) ?? root.id)]);
}

/** A key pressed while the selection may have the keyboard, by Windows virtual-key code. */
export interface SelectionKey {
  readonly code: number;
  readonly control: boolean;
  readonly shift: boolean;
  readonly alt: boolean;
}

/** What answers for one sidebar's selection: whether it took the command or key. */
type SelectionTaker = (command: string | null, key: SelectionKey | null) => boolean;

/**
 * The commands and keys each sidebar's selection answers before the window,
 * while it has the keyboard: the window's own, and the Getting Started
 * practice's while the guide shows. Each answers only for a selection that
 * has the keyboard, so at most one takes a key.
 */
const takers = new Set<SelectionTaker>();

/**
 * Whether the selection took `command`, which `key` pressed, so the window
 * leaves it alone: Ctrl+W archives the selection, and a key the selection
 * answers, such as Ctrl+D duplicating it, is the selection's before any
 * command's, as the Mac's selection monitor sees keys first.
 */
export function selectionTakes(command: string | null, key: SelectionKey | null): boolean {
  for (const take of takers) if (take(command, key)) return true;
  return false;
}

/** Registers what answers `selectionTakes` while a sidebar shows. */
export function registerSelectionTaker(take: SelectionTaker): () => void {
  takers.add(take);
  return () => void takers.delete(take);
}

/**
 * Whether the keys pressed now act on an engaged selection: neither a page, a
 * text field nor an open menu has them, as the Mac's `hasKeyboard` decides.
 */
export function selectionHasKeyboard(selection: SidebarSelection): boolean {
  if (!selection.engaged) return false;
  const active = document.activeElement;
  if (active instanceof HTMLEmbedElement) return false;
  if (active instanceof HTMLInputElement || active instanceof HTMLTextAreaElement) return false;
  return !(active instanceof HTMLElement && active.isContentEditable);
}
