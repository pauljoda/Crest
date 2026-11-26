import {
  ExternalLocalDocument,
  ExternalWebLink,
  OpenTab,
  RouteExternalLink,
  RouteLocalDocument,
  TabPlacement,
} from "@crest/contracts";

import type { Session } from "./boot";
import { unlockSpace } from "./spaces/space-access";

/**
 * BrowserMacExternalOpening, as Windows opens what another app hands Crest:
 * the links and documents Windows passes chrome.exe when Crest is their
 * handler, or someone runs it with them. The shell hands them to the window
 * in use with how the windows stack, front first, and that window opens
 * them where the core places them: the frontmost window over the person's
 * own Spaces, in the Space the core routes a link to, or for a document the
 * Space that window shows. Windows has no Quick Window yet, so a link the
 * core would open in one opens as a tab in that Space instead. Unlocking a
 * Space that asks for it stays here, since it asks the person.
 *
 * Starts this window hearing them, and takes any a launch brought before a
 * window could open them. Answers the call that stops it hearing more.
 */
export function opensExternal(session: Session): () => void {
  const shell = session.shell;
  if (!shell) return () => {};
  // Opens run one after another, in the order Windows handed them over.
  let queue = Promise.resolve();
  const enqueue = (urls: readonly string[], stack: readonly string[]) => {
    queue = queue.then(() => open(session, urls, stack)).catch(() => undefined);
  };
  shell.onOpenExternal = enqueue;
  void shell.takeLaunchOpens().then(({ urls, stack }) => {
    if (urls.length) enqueue(urls, stack);
  });
  return () => {
    if (shell.onOpenExternal === enqueue) shell.onOpenExternal = undefined;
  };
}

/** Opens `urls`: the documents together, then each link in turn. */
async function open(session: Session, urls: readonly string[], frontFirst: readonly string[]) {
  const { core } = session;
  // The core names windows by their identities, which the shell spells in capitals.
  const stack = frontFirst.map((id) => id.toLowerCase());
  if (!stack.includes(session.windowId)) stack.push(session.windowId);
  const documents: string[] = [];
  const links: string[] = [];
  for (const address of urls) {
    let url: URL;
    try {
      url = new URL(address);
    } catch {
      continue;
    }
    if (url.protocol === "file:") {
      const facts = { isFile: true, hasUser: url.username !== "", hasPath: url.pathname.length > 1, host: url.hostname || null };
      if ((await core.query(ExternalLocalDocument({ facts }))).accepted) documents.push(url.href);
    } else {
      const scheme = url.protocol.replace(/:$/, "");
      if ((await core.query(ExternalWebLink({ scheme, host: url.hostname || null }))).accepted) links.push(url.href);
    }
  }
  if (documents.length) await openDocuments(session, documents, stack);
  for (const link of links) await openLink(session, link, stack);
}

/**
 * Opens a link from another app as a tab in the window and Space the core
 * routes it to, after the tab that window shows there, and brings the window
 * forward. The core never routes one to a locked Space, so the unlock only
 * confirms the Space is still open to this process.
 */
async function openLink(session: Session, url: string, stack: readonly string[]) {
  const placement = await session.core.query(RouteExternalLink({ windowIds: stack, url }));
  const windowId = placement.windowId && !placement.opensWindow ? placement.windowId : session.windowId;
  if (!placement.spaceId || !(await unlocked(session, placement.spaceId))) return;
  const opened = await openTab(session, windowId, placement.spaceId, url, shownTab(session, windowId, placement.spaceId));
  if (opened) await present(session, windowId);
}

/**
 * Opens documents another app handed Crest as tabs, one after another, in
 * the Space the frontmost window shows, unlocking it first when it asks.
 */
async function openDocuments(session: Session, urls: readonly string[], stack: readonly string[]) {
  const placement = await session.core.query(RouteLocalDocument({ windowIds: stack }));
  const windowId = placement.windowId && !placement.opensWindow ? placement.windowId : session.windowId;
  if (!placement.spaceId || !(await unlocked(session, placement.spaceId))) return;
  let after = shownTab(session, windowId, placement.spaceId);
  let opened = false;
  for (const url of urls) {
    const tabId = await openTab(session, windowId, placement.spaceId, url, after);
    if (!tabId) continue;
    after = tabId;
    opened = true;
  }
  if (opened) await present(session, windowId);
}

async function unlocked(session: Session, spaceId: string): Promise<boolean> {
  const space = session.core.state.workspaces.get(session.workspaceId)?.spaces.get(spaceId);
  return !!space && (await unlockSpace(session, space));
}

/** The tab `windowId` shows in `spaceId`, which a new tab there follows. */
function shownTab(session: Session, windowId: string, spaceId: string): string | null {
  return session.core.state.windows.get(windowId)?.shownTabs.find((shown) => shown.spaceId === spaceId)?.tabId ?? null;
}

/** Opens `url` as a tab the window shows, answering the tab, or null when the core refused it. */
async function openTab(session: Session, windowId: string, spaceId: string, url: string, afterTabId: string | null) {
  const tabId = crypto.randomUUID();
  try {
    await session.core.send(OpenTab({
      workspaceId: session.workspaceId, windowId, spaceId, tabId,
      content: { address: url, view: null, title: null }, placement: TabPlacement.current, afterTabId,
      shows: true, placesAsNewTab: false, savesInSavedFolder: false,
    }));
    return tabId;
  } catch {
    return null;
  }
}

/** Brings the window an open landed in forward, and Crest with it. */
async function present(session: Session, windowId: string) {
  await session.shell?.focusWindow(windowId.toUpperCase());
}
