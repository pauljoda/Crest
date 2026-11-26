import { AdjacentDirection, ShowAdjacentSpace, ShowSpace } from "@crest/contracts";
import type { CrestCore } from "@crest/core-client";

import { pageStills } from "./page-stills";
import { spacePager } from "./space-pager";

/**
 * Shows `spaceId` in the window, as a click on its crest or its palette row
 * asks: the Space pager slides there at once, and the window asks the core
 * for it as the strip lands, as a swipe does (BrowserWindow's pager), so the
 * window draws the new Space at rest rather than in the slide's first frames,
 * which drawing it would hold back. A command run before it lands asks then.
 * Where the strip can't slide, the core is asked at once.
 */
export function showSpace(core: CrestCore, windowId: string, spaceId: string): Promise<unknown> {
  if (spacePager.lead(spaceId, true)) return Promise.resolve();
  pageStills.leaving(core);
  return core.send(ShowSpace({ windowId, spaceId }));
}

/**
 * Shows `spaceId` in the window at once, as a key asks, whose commands may
 * follow straight after: the pages the window leaves are pictured while they
 * still show, the slide starts, and the core is asked with the frame that
 * hands the slide to the compositor. A change the core refuses puts the strip
 * back.
 */
export function showSpaceNow(core: CrestCore, windowId: string, spaceId: string): Promise<unknown> {
  pageStills.leaving(core);
  const led = spacePager.lead(spaceId);
  return afterSlideStarts(led, () => core.send(ShowSpace({ windowId, spaceId }))).catch((error: unknown) => {
    spacePager.abandon(spaceId);
    throw error;
  });
}

/** Shows the next or previous Space, around the ends, as `showSpaceNow` does. */
export function showAdjacentSpace(core: CrestCore, windowId: string, direction: 1 | -1): Promise<unknown> {
  const target = spacePager.noteStep(direction);
  pageStills.leaving(core);
  const led = target !== null && spacePager.lead(target);
  const intent = ShowAdjacentSpace({ windowId, direction: direction > 0 ? AdjacentDirection.next : AdjacentDirection.previous });
  return afterSlideStarts(led, () => core.send(intent)).catch((error: unknown) => {
    if (target) spacePager.abandon(target);
    throw error;
  });
}

/**
 * Asks the core once the slide the pager just started has reached the
 * compositor, which takes its animations with the next frame: asked at
 * once, the core's answer would come first, and the window drawing the new
 * Space would hold that frame back, and the slide's start with it. A window
 * that draws no frame, hidden behind another, asks a moment later. Without a
 * slide, it asks at once.
 */
function afterSlideStarts<T>(led: boolean, ask: () => Promise<T>): Promise<T> {
  if (!led) return ask();
  return new Promise<T>((resolve, reject) => {
    let asked = false;
    const once = () => {
      if (asked) return;
      asked = true;
      ask().then(resolve, reject);
    };
    requestAnimationFrame(once);
    setTimeout(once, 50);
  });
}
