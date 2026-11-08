# Content blocking

Crest blocks ads and trackers with filter lists in EasyList and uBlock Origin
syntax, matched by Brave's open-source engine,
[adblock-rust](https://github.com/brave/adblock-rust), which the core links as
its content filter (`CrestCore/native/ContentFilter`). The core owns the lists,
their updates, each Space's choice and the sites where a Space turned blocking
off, and it produces what each engine enforces.

## Lists

`FilterList` in the core is the catalog: EasyList, EasyPrivacy, uBlock Origin's
own lists, regional lists, and opt-in lists for annoyances and cookie notices,
some of them AdGuard's builds for uBlock Origin. A list is on by default, on by
default for readers of its language, or off, and the person's own choices
override that. The choices are device preferences and do not sync.

The person can also add up to 30 lists by address (`AddCustomFilterList`), turn
each on or off and remove it, and keep their own filters, in the lists' syntax
and up to 512 KB, as My Filters (`SetCustomFilters`). Both are device
preferences, kept by the device store, and apply beside the catalog's lists. A
list the person added takes its title from its `! Title:` header.

Crest never ships a copy of a list. The platform downloads what the core says is
due (`DueFilterDownloads`) from the list's maintainers, with the validators of
the copy it holds, and hands the result back (`FilterDownloadFetched`,
`FilterDownloadNotModified`, `FilterDownloadFailed`). It downloads over https
alone, redirects included, reads each list as it arrives and stops one that
grows past 15 MB (`FilterDownloadTooLarge`); the core refuses a list over that
size or 300,000 rules, keeps the copy it held, and Settings says so under the
list. It asks when the app starts, every hour, and whenever the lists change,
so a list the person adds or turns on arrives at once. The core hashes, counts
and writes a download before the turn that publishes it, never under the
app's lock. The core keeps each copy as a file in a
`ContentFilter` folder beside the session file, outside the session, its sync
and its recovery checkpoint. A list is due again when its `Expires` header
says, kept between twelve hours and a week and spread by a tenth so devices do
not ask at once; a failed download is retried later each time.

The resources that scriptlets and redirect filters name are downloaded the same
way, from uBlock Origin's own release, which
`Scripts/control-plane/ublock-resources` converts into the engine's format and
publishes as a release asset. They are data the engine loads, not part of
Crest's binary.

uBlock Origin's lists wrap platform-specific rules in `!#if` blocks, which the
engine would read as comments. `FilterListText` resolves them for the platform
before the engine sees them: Safari's conditions for WebKit, plus `env_mobile`
on iPhone and iPad, and Chromium's for Chromium.

Until the first list arrives, Crest's own baseline rules block third-party
loads from well-known advertising and analytics hosts. They stay beside the
lists afterwards.

## Spaces and sites

A Space's `ContentBlockingPolicy` decides whether it blocks at all: Balanced
applies the lists, Off blocks nothing. The Space's privacy settings switch it.

A page's actions turn blocking off, or on again, for the site it shows, in its
Space (`SetSiteContentBlocking`). The device store keeps a persistent Space's
sites; any other Space's, such as a private one's, last as long as the process.
A deleted Space's sites go with it. `ContentBlockingApplies` answers whether a
page of a Space blocks on a site.

## WebKit

WebKit has no per-request callback, so the core converts the lists into WebKit
content rules on a worker, never under its lock, and announces the result as a
`ContentRuleListSet`. WebKit evaluates each compiled list on its own, so an
exception in one list never reaches a rule in another: the core converts every
list that is on together and splits the rules into lists of at most 70,000,
well under WebKit's 150,000, with every exception repeated at the end of each.
Each list's identifier changes with its rules, so a rule-list store compiles
it once and keeps it across launches; the core answers the source of one the
store lacks (`ContentRuleListSource`), and the lists Crest compiled earlier are
removed when no set names them.

Each page owns its user content controller. A main-frame navigation installs
or removes Crest's lists for the site it goes to before the page loads it, so a
site's switch costs no compilation. A list update takes effect on each page's
next navigation; the page whose site the person switched reloads. The lists
carry the sites' own hiding rules; generic hiding, and what WebKit cannot
express, such as procedural element hiding, are left to the cosmetic bridge
below. A main-frame navigation also installs the site's scriptlets
(`PageScriptlets`) as one user script in the page's own world, at document
start, in place of the previous site's (`BrowserPageScriptletSession`).
WebKit cannot replace a response, so a redirect filter is left out and its
request allowed. An isolated launch compiles into a store of its own under the
temporary folder.

## Chromium

Chromium checks each request itself, so its pages use the engine filter
directly rather than converted rules. The core compiles every list that is on,
resolved for Chromium's conditions (`env_chromium`), into one filter on a
worker, saves it beside the lists so the next launch only loads it, and puts it
in a `ContentFilterSlot`. The engine binding finds the slot once, through
`crest_app_content_filter_slot`, and checks each request with
`crest_content_filter_slot_check` on a sequence of its own: the check takes no
core lock and runs no managed code, and a check under way when the filter is
replaced finishes with the one it began with.

The host's `content-filter.patch` puts a filtering URL loader factory in front of
each Crest page's document and frame-navigation factories. A request the filter
blocks fails with `ERR_BLOCKED_BY_CLIENT`; a top-level document is never
blocked. Each redirect a request it allowed is about to follow is checked the
same way, as the request it becomes. The filter judges every request as part
of the top-level page, as Brave does: a filter's `$domain` and `$third-party`
options and the site's own rules are about the page the tab shows, not the
frame that asks. Whether a page blocks at all is the core's answer at each main-frame
commit (`PageBlocksContent`), the same as `ContentBlockingApplies`, so a site's
switch takes effect when the page reloads, and a list update at once.

A request a redirect filter matches is answered by the binding itself with the
resource the filter names, such as an empty script or a transparent image, so
a page that expects the script still runs; a frame is never redirected. Before
each main-frame commit the binding asks the core for the site's scriptlets
(`PageInjectedScript`) and hands them to the committing frame through
Chromium's `js_injection` component, which the patch wires into the renderer:
the frame runs them in the page's own world as the document starts, before its
own scripts. uBlock Origin's scriptlets share a `scriptletGlobals` object, which
the core declares around them on both engines.

Element hiding on Chromium pages goes through the cosmetic bridge below, since
Chromium applies no hiding rules of its own.

## Cosmetic filtering

Blocking a request can leave the box it would have filled, so a page shows
empty space where an ad was. Crest's cosmetic bridge
(`BrowserCosmeticFilterContentBridge`) closes those boxes on both engines, as
ad blockers such as uBlock Origin do. It runs in every document, in Crest's
own content world, and asks the core (`DocumentCosmetics`), which answers from
its compiled filter for the page's Space and the site it shows:

- As the document starts: the site's hiding rules, and its procedural
  filters, which plain CSS cannot express, such as `:has-text()`, `:upward()`,
  `:matches-css()` and the `:remove()` and `:style()` actions. The bridge
  applies them and applies them again as the document changes.
- As elements appear: the generic hiding rules for the classes and ids they
  show, as style rules in one sheet the bridge adopts, and whether the frames,
  images and objects they load are ones the filter blocks; those elements
  collapse. The bridge puts the sheet back as the document changes if the page
  removes it, turns it off or deletes its rules.

Generic rules apply as elements appear on both engines, rather than through
WebKit's content rules before a page first renders: sites that check whether a
bait element was hidden at once otherwise take the hiding for blocking and
interrupt the page. An ad slot left with nothing to show also collapses: an
element named as one (`ad`, `advert`, `billboard`, `leaderboard`, `dfp` and the
like) or holding only an ad label such as "Advertisement", that shows no text,
image, video, frame or control, no image still to load and no background
image. A collapsed slot shows again when something it may show arrives inside
it, and the next sweep looks at it afresh, a few times at most. Crest's
baseline also hides a JW Player video while it floats over the page.

A page whose Space does not block on the site gets nothing, and the bridge
stops. The compiled filter is built on every platform for this: with
Chromium's `!#if` conditions on the Mac, where Chromium also checks requests
against it, and with Safari's on iPhone and iPad.

## Blocking an element

Block Element, in the page menu, the page's context menu on the Mac and the
page actions on iPhone and iPad, starts the bridge's element picker in the
page's top document. The picker outlines the item under the pointer, or starts
from the one the person right-clicked, and reports what it holds to the page's
`BrowserElementPicker`, which the app's own bar shows in Liquid Glass
(`BrowserElementPickerBar`): the selector of the pick on a row of its own, and
below it the controls that choose the element around it or inside it, cancel,
and block it. The picker writes the shortest selector that matches the element
alone, by its names where they are unique and otherwise by its place in the
page, and offers no Block for an element it cannot single out. Only the
person's own input picks and blocks: events the page makes up pass through, and
the app keeps only the selector its bar shows. Blocking dissolves what it
matches and the core adds it to My Filters as a rule for the page's host
(`BlockElement`), so it applies from then on, on both engines, like any filter
the person wrote. The core refuses a selector that could be more than a hiding
rule for that host: one with a control character or line separator, one a list
reads as a scriptlet or an HTML filter, another rule's separator, or one over
1 KB. The picker ends when its document goes, into the back-forward cache, to
another history entry, or when the page navigates.

Show Blocked Elements, offered where the page's host has such rules
(`PageBlocksElements`), removes them (`UnblockElements`) and reloads the page
once the core's rules without them are in force (`BrowserBlockedElements`), as
Safari's Show Hidden Items does.
