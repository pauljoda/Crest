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

Crest never ships a copy of a list. The platform downloads what the core says is
due (`DueFilterListFetches`) from the list's maintainers, with the validators of
the copy it holds, and hands the result back (`FilterListFetched`,
`FilterListNotModified`, `FilterListFetchFailed`). The core keeps each copy as a
file in a `ContentFilter` folder beside the session file, outside the session,
its sync and its recovery checkpoint. A list is due again when its `Expires`
header says, kept between twelve hours and a week and spread by a tenth so
devices do not ask at once; a failed download is retried later each time.

uBlock Origin's lists wrap platform-specific rules in `!#if` blocks, which the
engine would read as comments. `FilterListText` resolves them for the platform
before the engine sees them: Safari's conditions for WebKit, plus `env_mobile`
on iPhone and iPad.

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
next navigation; the page whose site the person switched reloads. Rules that
WebKit cannot express, such as scriptlets, redirects and procedural element
hiding, are left out for now. An isolated launch compiles into a store of its
own under the temporary folder.

## Chromium

Chromium pages do not yet enforce the lists; until they do, the Chromium
registration declares `content-blocking` unavailable, and blocking there comes
from an extension the person installs.
