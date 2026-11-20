import { type ExtensionAction, ExtensionChange, PageExtensions, PinnedExtensions, type SpaceState } from "@crest/contracts";
import { useEffect, useMemo, useState, useSyncExternalStore } from "react";

import type { Session } from "../boot";
import { change, extensionPages, extensions, openExtensionPage } from "../extensions";
import { showContextMenu } from "../menus";
import { notices } from "../notices";
import { Symbol } from "../symbols";

/** An extension's action as a button shows it: the engine's action, its icon as an address. */
export interface ActionPresentation extends ExtensionAction {
  readonly iconUrl: string | null;
}

/** The icons of `actions`, as addresses that live while the actions do. */
function useActionIcons(actions: readonly ExtensionAction[]): readonly ActionPresentation[] {
  const presented = useMemo(() => actions.map((action) => ({
    ...action,
    iconUrl: action.icon && action.icon.length > 0 ? URL.createObjectURL(new Blob([action.icon as BlobPart])) : null,
  })), [actions]);
  useEffect(() => () => {
    for (const action of presented) if (action.iconUrl) URL.revokeObjectURL(action.iconUrl);
  }, [presented]);
  return presented;
}

/**
 * The Mac's ChromiumExtensionStore actions: a Space's pinned actions, from its
 * profile, in the order the person left them, with the shown page's own state
 * (badge, icon, whether it runs there and opens a popup) laid over each; and
 * every action the page offers. Asked again whenever an engine says the
 * profile's extensions changed, and as the page moves on.
 */
export function useExtensionActions(session: Session, profileId: string, pageId: string | null, pageKey: string) {
  useSyncExternalStore((listener) => extensions.subscribe(listener), () => extensions.version);
  const revision = extensions.revision;
  const [pinned, setPinned] = useState<readonly ExtensionAction[]>([]);
  const [page, setPage] = useState<readonly ExtensionAction[]>([]);
  useEffect(() => {
    let current = true;
    void session.core.request(PinnedExtensions({ profileId })).then((list) => current && setPinned(list.actions), () => current && setPinned([]));
    if (pageId) {
      void session.core.request(PageExtensions({ pageId })).then((list) => current && setPage(list.actions), () => current && setPage([]));
    } else {
      setPage([]);
    }
    return () => {
      current = false;
    };
  }, [session, profileId, pageId, pageKey, revision]);
  const live = new Map(page.map((action) => [action.id, action]));
  const overlaid = useMemo(() => pinned.map((action) => {
    const tab = live.get(action.id);
    return tab ? { ...tab, pinned: true } : action;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }), [pinned, page]);
  return { pinned: useActionIcons(overlaid), page: useActionIcons(page) };
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
  void showContextMenu(session.shell, at, [
    {
      title: action.pinned ? "Unpin" : "Pin to Sidebar",
      run: () => void change(session, space.id, action.id, action.pinned ? ExtensionChange.Unpin : ExtensionChange.Pin)
        .then(() => extensions.changedHere()),
    },
    "separator",
    ...(installed?.optionsUrl && installed.enabled
      ? [{ title: "Extension Settings", run: () => openExtensionPage(session, space, installed.optionsUrl!) }] : []),
    { title: "Manage Extension", run: () => openExtensionPage(session, space, extensionPages.details(action.id)) },
    ...(installed?.changeable === false ? [] : ["separator" as const, { title: "Remove from Space…", run: () => extensions.askRemoval(space.id, action.id) }]),
  ]);
}

/** An action's icon, with its badge where it has one, as BrowserExtensionActionArtwork draws them. */
export function ActionArtwork({ action, size }: { action: ActionPresentation; size: number }) {
  return (
    <span className="extension-artwork" style={{ width: size, height: size }}>
      {action.iconUrl ? <img src={action.iconUrl} alt="" width={size} height={size} /> : <Symbol name="puzzlepiece.extension" size={size} />}
      {action.badge && <span className="extension-badge">{action.badge}</span>}
    </span>
  );
}

/**
 * The Mac's BrowserPinnedExtensionStrip in the sidebar: the Space's pinned
 * actions above its tabs, each a 24-point tile that runs it, on the same
 * surface as the address field, shown only while it holds any.
 */
export function PinnedExtensionStrip({ session, space, pageId, pageKey }: {
  session: Session;
  space: SpaceState;
  pageId: string | null;
  pageKey: string;
}) {
  const { pinned } = useExtensionActions(session, space.profileId, pageId, pageKey);
  if (pinned.length === 0) return null;
  return (
    <div className="extension-strip" role="toolbar" aria-label="Pinned Extensions">
      {pinned.map((action) => (
        <button key={action.id} type="button" className={`extension-tile${action.enabled ? "" : " unavailable"}`}
          aria-label={action.name} title={action.name}
          onClick={(event) => void runExtensionAction(session, action, pageId, event.currentTarget)}
          onContextMenu={(event) => {
            event.preventDefault();
            extensionMenu(session, space, action, event);
          }}>
          <ActionArtwork action={action} size={16} />
        </button>
      ))}
    </div>
  );
}

/**
 * The Mac's BrowserSiteExtensionsSection in Site Controls: every action the
 * page offers, four to a row, each running on a click, with a pin that shows
 * on hover; and the way to manage extensions.
 */
export function SiteExtensionsSection({ session, space, pageId, pageKey, onRun, onManage }: {
  session: Session;
  space: SpaceState;
  pageId: string;
  pageKey: string;
  /** Puts Site Controls away before an action runs, so its popup opens over the page. */
  onRun: (run: () => void) => void;
  onManage: () => void;
}) {
  const { page } = useExtensionActions(session, space.profileId, pageId, pageKey);
  return (
    <div className="site-extensions">
      <div className="site-extensions-header">
        <span>Extensions</span>
        <button type="button" className="site-extensions-manage" aria-label="Manage Extensions" title="Manage Extensions" onClick={onManage}>
          <Symbol name="plus" size={11} strokeWidth={2.5} />
        </button>
      </div>
      {page.length === 0 ? (
        <span className="site-extensions-empty"><Symbol name="puzzlepiece.extension" size={12} /> No extension actions for this page</span>
      ) : (
        <div className="site-extensions-grid">
          {page.map((action) => (
            <div key={action.id} className="site-extension">
              <button type="button" className={`site-extension-action${action.enabled ? "" : " unavailable"}`} aria-label={action.name} title={action.name}
                onClick={(event) => {
                  const button = event.currentTarget;
                  const bounds = button.getBoundingClientRect();
                  // The popup opens where the button was, once the panel has gone.
                  onRun(() => void runExtensionAction(session, action, pageId, { getBoundingClientRect: () => bounds } as Element));
                }}
                onContextMenu={(event) => {
                  event.preventDefault();
                  extensionMenu(session, space, action, event);
                }}>
                <ActionArtwork action={action} size={17} />
              </button>
              <button type="button" className={`site-extension-pin${action.pinned ? " pinned" : ""}`}
                aria-label={action.pinned ? `Unpin ${action.name}` : `Pin ${action.name}`} title={action.pinned ? "Unpin" : "Pin to Sidebar"}
                onClick={() => void change(session, space.id, action.id, action.pinned ? ExtensionChange.Unpin : ExtensionChange.Pin)
                  .then(() => extensions.changedHere())}>
                <Symbol name={action.pinned ? "pin.fill" : "pin"} size={9} />
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
