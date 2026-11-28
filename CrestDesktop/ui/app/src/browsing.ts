import { CloseTab, ReloadPage, StepHistory, StopLoading } from "@crest/contracts";

import type { Session } from "./boot";

/**
 * What a person does with the window's pages and tabs. History moves and tab
 * changes are the core's intents; reload and stop are the page's engine's own
 * view work, asked of it directly.
 */
export class Browsing {
  constructor(private readonly session: Session) {}

  back(pageId: string) {
    return this.session.core.send(StepHistory({ pageId, offset: -1 }));
  }

  forward(pageId: string) {
    return this.session.core.send(StepHistory({ pageId, offset: 1 }));
  }

  reload(pageId: string, bypassesCache = false) {
    return this.direct(ReloadPage({ pageId, bypassesCache }));
  }

  stop(pageId: string) {
    return this.direct(StopLoading({ pageId }));
  }

  closeTab(spaceId: string, tabId: string) {
    return this.session.core.send(
      CloseTab({
        workspaceId: this.session.workspaceId,
        windowId: this.session.windowId,
        spaceId,
        tabId,
        returnTabId: null,
      }),
    );
  }

  /** View work only Crest's Chromium carries; the development engine has none. */
  private direct(request: Parameters<Session["core"]["request"]>[0]) {
    return this.session.shell ? this.session.core.request(request) : Promise.resolve(false);
  }
}
