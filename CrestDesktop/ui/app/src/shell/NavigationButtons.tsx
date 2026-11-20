import type { PageState } from "@crest/contracts";

import type { Browsing } from "../browsing";
import { ChromeButton } from "./ChromeButton";

/**
 * Back, forward, and reload or stop, for the page the window shows. Back and
 * forward are arrows, as Windows browsers draw them, where the Mac's are
 * chevrons.
 */
export function NavigationButtons({ browsing, page }: { browsing: Browsing; page: PageState | null }) {
  const live = page?.live;
  return (
    <>
      <ChromeButton symbol="arrow.left" label="Back" disabled={!live?.canGoBack}
        onClick={() => page && void browsing.back(page.id)} />
      <ChromeButton symbol="arrow.right" label="Forward" disabled={!live?.canGoForward}
        onClick={() => page && void browsing.forward(page.id)} />
      <ChromeButton symbol={live?.isLoading ? "xmark" : "arrow.clockwise"} label={live?.isLoading ? "Stop" : "Reload"}
        disabled={!page}
        onClick={() => page && void (live?.isLoading ? browsing.stop(page.id) : browsing.reload(page.id))} />
    </>
  );
}
