import { type ExtensionAction, ExtensionChange, PageExtensions, PinnedExtensions, type SpaceState } from "@crest/contracts";
import { untrack } from "svelte";

import type { Session } from "../../boot";
import { change, extensionPages, extensions, openExtensionPage } from "../../extensions";
import { showContextMenu } from "../../menus";
import { notices } from "../../notices";
import { reader } from "../../reactive";

/** An extension's action as a button shows it: the engine's action, its icon as an address. */
export interface ActionPresentation extends ExtensionAction {
  readonly iconUrl: string | null;
}

/** The extensions store's version, followed by the expression that reads it. */
const extensionsVersion = reader((listener) => extensions.subscribe(listener), () => extensions.version);

/** The icons of `actions`, as addresses that live while the actions do. */
function useActionIcons(actions: () => readonly ExtensionAction[]): { readonly current: readonly ActionPresentation[] } {
  const presented = $derived(actions().map((action) => ({
    ...action,
    iconUrl: action.icon && action.icon.length > 0 ? URL.createObjectURL(new Blob([action.icon as BlobPart])) : null,
  })));
  $effect(() => {
    const shown = presented;
    return () => {
      for (const action of shown) if (action.iconUrl) URL.revokeObjectURL(action.iconUrl);
    };
  });
  return {
    get current() {
      return presented;
    },
  };
}

/**
 * The Mac's ChromiumExtensionStore actions: a Space's pinned actions, from its
 * profile, in the order the person left them, with the shown page's own state
 * (badge, icon, whether it runs there and opens a popup) laid over each; and
 * every action the page offers. Asked again whenever an engine says the
 * profile's extensions changed, and as the page moves on.
 *
 * Call during a component's initialization; read `.current.pinned` and
 * `.current.page`.
 */
export function useExtensionActions(session: Session, profileId: () => string, pageId: () => string | null, pageKey: () => string): {
  readonly current: { readonly pinned: readonly ActionPresentation[]; readonly page: readonly ActionPresentation[] };
} {
  const revision = $derived((extensionsVersion(), extensions.revision));
  let pinned = $state.raw<readonly ExtensionAction[]>([]);
  let page = $state.raw<readonly ExtensionAction[]>([]);
  $effect(() => {
    const profile = profileId();
    const shownPage = pageId();
    void pageKey();
    void revision;
    return untrack(() => {
      let current = true;
      void session.core.request(PinnedExtensions({ profileId: profile })).then((list) => {
        if (current) pinned = list.actions;
      }, () => {
        if (current) pinned = [];
      });
      if (shownPage) {
        void session.core.request(PageExtensions({ pageId: shownPage })).then((list) => {
          if (current) page = list.actions;
        }, () => {
          if (current) page = [];
        });
      } else {
        page = [];
      }
      return () => {
        current = false;
      };
    });
  });
  const overlaid = $derived.by(() => {
    const live = new Map(page.map((action) => [action.id, action]));
    return pinned.map((action) => {
      const tab = live.get(action.id);
      return tab ? { ...tab, pinned: true } : action;
    });
  });
  const pinnedIcons = useActionIcons(() => overlaid);
  const pageIcons = useActionIcons(() => page);
  const current = $derived({ pinned: pinnedIcons.current, page: pageIcons.current });
  return {
    get current() {
      return current;
    },
  };
}

/**
 * Runs an extension's action from its button, as the Mac's runs it: for the
 * shown page, its popup opening beside the button. With no page open, an
 * action has nothing to run on, which it says.
 */
export async function runExtensionAction(session: Session, action: ExtensionAction, pageId: string | null, button: Element) {
  if (!session.shell) return;
  if (!pageId) {
    notices.post({ message: "This extension action needs an open page.", symbol: "puzzlepiece.extension" });
    return;
  }
  const bounds = button.getBoundingClientRect();
  const result = await session.shell.runExtension(action.id, pageId, {
    x: bounds.left, y: bounds.top, width: bounds.width, height: bounds.height,
  }).catch(() => null);
  if (!result?.ran) notices.post({ message: `${action.name} can’t run on this page.`, symbol: "puzzlepiece.extension" });
}

/** An extension's menu, as the Mac's store presents it: pinning, its settings and page in Chromium, removal. */
export function extensionMenu(session: Session, space: SpaceState, action: ExtensionAction, at: { clientX: number; clientY: number }) {
  const installed = session.core.state.installedExtensions.get(space.profileId)?.find((item) => item.id === action.id);
  void showContextMenu(at, [
    {
      title: action.pinned ? "Unpin" : "Pin to Sidebar", icon: action.pinned ? "pin.slash" : "pin",
      run: () => void change(session, space.id, action.id, action.pinned ? ExtensionChange.Unpin : ExtensionChange.Pin)
        .then(() => extensions.changedHere()),
    },
    "separator",
    ...(installed?.optionsUrl && installed.enabled
      ? [{ title: "Extension Settings", icon: "gearshape", run: () => openExtensionPage(session, space, installed.optionsUrl!) }] : []),
    { title: "Manage Extension", icon: "slider.horizontal.3", run: () => openExtensionPage(session, space, extensionPages.details(action.id)) },
    ...(installed?.changeable === false ? [] : ["separator" as const, { title: "Remove from Space…", icon: "trash", run: () => extensions.askRemoval(space.id, action.id) }]),
  ]);
}
