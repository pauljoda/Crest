---
title: Content blocking and site permissions
description: Block ads and trackers everywhere, and control camera, microphone, pop-ups, downloads, and external apps per Space.
slug: /content-blocking-and-site-permissions
keywords: [ad blocking, content blocking, ads, trackers, filter lists, strict, block element, permissions, camera, microphone, pop-ups, downloads]
---

# Content blocking and site permissions

Privacy decisions belong to the current Space. A permission granted to a work account does not silently become a permission for the same host in Personal. The Spaces of a [Sub-Space](../spaces/sub-spaces.md) group share their site permissions. Ad blocking is the exception: it applies to every Space alike.

## Content blocking

Crest blocks ads and trackers with the filter lists that ad blockers use: EasyList, EasyPrivacy and uBlock Origin's lists, plus a regional list for your language. It applies on iPhone, iPad and Mac, to Chromium and WebKit pages alike. Blocked ads leave no empty boxes behind, and floating video players are hidden. Like uBlock Origin, Crest also runs the small fixes the lists include for sites that work around ad blockers. The lists download from their maintainers and stay up to date on their own.

Open **Settings → Ad Blocking** and choose how much Crest blocks:

- **Off** blocks nothing.
- **Balanced** blocks ads and trackers while keeping sites working. This is where Crest starts, unless you had turned blocking off in every Space, when it starts at Off.
- **Strict** also hides cookie notices and other annoyances, and adds AdGuard's ad list. A few sites may not work.

Each level turns the filter lists below it on or off. You can still turn a single list on or off; the setting then says **Customized**, and its reset button brings back the level's lists. **Update Now** downloads every list again.

Under **Your Lists**, subscribe to any other list by its address; it stays up to date like the built-in ones. Under **My Filters**, write your own rules, one per line, in the lists' syntax, then choose **Save**. Ad blocking settings stay on the device and don't sync.

To hide something the lists miss, choose **Block Element** from the page's actions, or on Mac from the **Page** menu or by right-clicking it. Point at the element, or tap it. The bar at the bottom shows what you picked; use its arrows to choose the larger element around it or the smaller one inside, then choose **Block**. Crest adds the rule to My Filters for that site. To bring back what you blocked on a site, choose **Show Blocked Elements** from the same place.

When a site doesn’t work with blocking, choose **Turn Off Blocking on** the site from the page’s actions, or assign **Toggle Content Blocking** a shortcut. The site stays unblocked in every Space until you turn blocking on again from the same place or from **Sites with Blocking Off** in Settings → Ad Blocking. Turned off from a private window, it stays unblocked only until Crest quits.

On Chromium pages, a content-blocking extension you install works alongside the lists. Extensions do not run on WebKit pages.

## Malicious sites and downloads

Crest's Chromium build doesn't use Google Safe Browsing or another site and download reputation service, so it cannot warn about every known phishing site or malicious download. Certificate checks, with revocation lists Crest keeps up to date, Chromium's sandbox, and warnings about executable or insecure downloads remain in place. Those checks do not determine whether a file is malware, and a completed download is not a safety verdict.

## Site permissions

Crest can remember decisions for:

- Camera
- Microphone
- Camera and microphone together
- Location
- Notifications
- Pop-ups
- Automatic downloads
- Opening external apps

Open Site Controls on the affected page to inspect or reset the decision. The Space’s privacy settings list its saved site permissions: on Mac, open Settings, select the Space in the sidebar, then select **Privacy**; on iPhone and iPad, open **Settings → Privacy** and choose the Space.

Screen sharing asks what to share each time. You can block it for a site, but cannot preapprove a tab, screen or window. On pages that run in Chromium on Mac, Crest first lists the tabs in the same Space, and can share a tab's audio. Choose Window or Screen to use the macOS picker instead, which shares no audio. While a tab is shared, it and the sharing page show a bar with Stop sharing, and the shared tab is outlined in the sidebar. Minimize a bar to hide it until you come back to that tab. To stop from the sidebar, right-click either tab and choose Stop Sharing. Clicking the sharing symbol on a shared tab also offers to go to the tab it is shared to.

## Notifications

Allow the site in Crest and allow Crest in macOS notification settings to receive notifications. On Mac, **Settings → Privacy → System permissions** shows whether macOS allows it. Document notifications belong to their open page. Chromium also supports local service-worker and extension notifications while Crest runs, including a service worker's notification after its tab closes. Private profiles do not deliver these background notifications. Locking a Space or revoking its site permission withdraws notifications it can no longer show.

Remote Web Push delivery is not available in Crest's Chromium build: it needs Google's push service, which gives the browser a persistent identity. Local service-worker notifications do not mean that a site can receive server pushes or wake Crest after it quits.

## Reset a site

If a site behaves as though an old choice still applies, first reset its saved permission rather than deleting the entire Space. [Clearing a site's data](./clear-website-data.md) is broader: it signs you out and removes what the site stored in that Space.

## Extension site access

Extension permissions are a separate layer. An extension may be installed but still blocked from the current host, or it may require approval for additional sites. See [Manage extension permissions and site access](../extensions/manage-permissions-site-access.md) for the extension-specific controls.
