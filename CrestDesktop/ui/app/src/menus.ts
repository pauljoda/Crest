import { type KeyCombination, ShortcutModifiers } from "@crest/contracts";
import type { ShellMenuItem, ShellTransport } from "@crest/core-client";

import { keyCode } from "./shortcuts";

let menusOpen = 0;

/** Whether one of the interface's menus is open, which keeps a floating sidebar out. */
export function isMenuOpen(): boolean {
  return menusOpen > 0;
}

/** One thing a menu offers: what it is called, whether it can act now, and what it does. */
export interface MenuAction {
  readonly title: string;
  readonly run: () => void;
  readonly enabled?: boolean;
  readonly checked?: boolean;
  /** The keys the command it runs answers to, shown beside it. */
  readonly keys?: KeyCombination | null;
}

/** A submenu, such as Move to Space. */
export interface MenuGroup {
  readonly title: string;
  readonly submenu: readonly MenuEntry[];
  readonly enabled?: boolean;
}

export type MenuEntry = MenuAction | MenuGroup | "separator";

/**
 * Runs `entries` as a context menu where `event` happened, as Windows' own
 * menus run, and does what the person chose. Separators at the ends or next
 * to each other, as hidden items leave them, are dropped.
 */
export async function showContextMenu(shell: ShellTransport | null, event: { clientX: number; clientY: number },
  entries: readonly MenuEntry[]) {
  if (!shell) return;
  const actions = new Map<string, () => void>();
  const describe = (list: readonly MenuEntry[]): ShellMenuItem[] => {
    const items: ShellMenuItem[] = [];
    for (const entry of list) {
      if (entry === "separator") {
        if (items.length > 0 && !("separator" in items[items.length - 1])) items.push({ separator: true });
        continue;
      }
      if ("submenu" in entry) {
        const submenu = describe(entry.submenu);
        if (submenu.length > 0) items.push({ title: entry.title, submenu, enabled: entry.enabled ?? true });
        continue;
      }
      const id = String(actions.size);
      actions.set(id, entry.run);
      const key = entry.keys ? keyCode(entry.keys) : null;
      items.push({
        id,
        title: entry.title,
        enabled: entry.enabled ?? true,
        ...(entry.checked === undefined ? {} : { checked: entry.checked }),
        ...(entry.keys && key !== null && !(entry.keys.modifiers & ShortcutModifiers.Control)
          ? {
            shortcut: {
              key,
              control: !!(entry.keys.modifiers & ShortcutModifiers.Command),
              shift: !!(entry.keys.modifiers & ShortcutModifiers.Shift),
              alt: !!(entry.keys.modifiers & ShortcutModifiers.Option),
            },
          }
          : {}),
      });
    }
    while (items.length > 0 && "separator" in items[items.length - 1]) items.pop();
    return items;
  };
  const items = describe(entries);
  if (items.length === 0) return;
  menusOpen++;
  let chosen: string | null;
  try {
    chosen = await shell.menu(items, event.clientX, event.clientY);
  } finally {
    menusOpen--;
  }
  if (chosen !== null) actions.get(chosen)?.();
}
