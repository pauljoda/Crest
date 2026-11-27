import type { FolderState, KeyCombination, SpaceBranding, SpaceState } from "@crest/contracts";

import { css } from "./branding";

let menusOpen = 0;

/** Whether one of the interface's menus is open, which keeps a floating sidebar out. */
export function isMenuOpen(): boolean {
  return menusOpen > 0;
}

/**
 * What a menu item shows before its title, as every menu row on the Mac
 * does: an SF Symbol for an action, one in a folder's colour for a folder or
 * group, or a Space's own identity for a Space, as Move to Space shows it.
 */
export type MenuIcon =
  | string
  | { readonly symbol: string; readonly tint: string }
  | { readonly space: { readonly symbol: string; readonly branding: SpaceBranding } };

/** A Space's row in a menu, under its crest, as the Mac's BrowserSpaceIdentityLabel. */
export function spaceMenuIcon(space: SpaceState): MenuIcon {
  return { space: { symbol: space.settings.symbol, branding: space.settings.look } };
}

/** The colour a folder or group wears until one is chosen, the Mac's folderDefault (Slate). */
export const folderDefault = { red: 0.43, green: 0.48, blue: 0.54, alpha: 1 };

/**
 * A folder's row in a menu: a group's stack, or a folder's own symbol, in its
 * colour, as the Mac's BrowserFolderMenuIcon and BrowserFolderArtwork.
 */
export function folderMenuIcon(folder: FolderState): MenuIcon {
  const symbol = folder.isGroup ? "rectangle.stack.fill" : folder.symbol || "folder.fill";
  return { symbol, tint: css(folder.color ?? folderDefault) };
}

/** One thing a menu offers: what it is called, whether it can act now, and what it does. */
export interface MenuAction {
  readonly title: string;
  readonly icon: MenuIcon;
  readonly run: () => void;
  readonly enabled?: boolean;
  readonly checked?: boolean;
  /** The keys the command it runs answers to, shown beside it. */
  readonly keys?: KeyCombination | null;
}

/** A submenu, such as Move to Space. */
export interface MenuGroup {
  readonly title: string;
  readonly icon: MenuIcon;
  readonly submenu: readonly MenuEntry[];
  readonly enabled?: boolean;
}

export type MenuEntry = MenuAction | MenuGroup | "separator";

/** A menu ready to show: no separator at either end or beside another, and no empty submenu. */
export type ShownEntry = MenuAction | (Omit<MenuGroup, "submenu"> & { readonly submenu: readonly ShownEntry[] }) | "separator";

/** Where a menu opens, in the window's coordinates, and what it offers. */
export interface MenuRequest {
  readonly x: number;
  readonly y: number;
  readonly entries: readonly ShownEntry[];
  /** Ends the menu, with what the person chose or nothing. */
  readonly finish: (chosen: MenuAction | null) => void;
}

/** The window's menu layer, which shows one menu at a time. */
let present: ((request: MenuRequest) => void) | null = null;

/** Lets the window's menu layer show menus; the returned function takes it back. */
export function presentMenusWith(presenter: (request: MenuRequest) => void): () => void {
  present = presenter;
  return () => {
    if (present === presenter) present = null;
  };
}

/** `entries` without the separators hidden items leave at the ends or beside each other, or submenus with nothing. */
export function shownEntries(entries: readonly MenuEntry[]): ShownEntry[] {
  const shown: ShownEntry[] = [];
  for (const entry of entries) {
    if (entry === "separator") {
      if (shown.length > 0 && shown[shown.length - 1] !== "separator") shown.push(entry);
      continue;
    }
    if ("submenu" in entry) {
      const submenu = shownEntries(entry.submenu);
      if (submenu.length > 0) shown.push({ ...entry, submenu });
      continue;
    }
    shown.push(entry);
  }
  while (shown[shown.length - 1] === "separator") shown.pop();
  return shown;
}

/**
 * Shows `entries` as a menu where `event` happened, in the window, and does
 * what the person chose once the menu has gone.
 */
export async function showContextMenu(event: { clientX: number; clientY: number }, entries: readonly MenuEntry[]) {
  const shown = shownEntries(entries);
  const presenter = present;
  if (shown.length === 0 || !presenter) return;
  menusOpen++;
  let chosen: MenuAction | null;
  try {
    chosen = await new Promise<MenuAction | null>((finish) => presenter({ x: event.clientX, y: event.clientY, entries: shown, finish }));
  } finally {
    menusOpen--;
  }
  chosen?.run();
}
