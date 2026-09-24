# Core architecture

Crest's state and app logic live in one portable core, `CrestCore`, written in
C#. Each platform supplies only its UI, its engine bindings and its OS
services. Adding a platform means writing those three things and nothing else.

This document is the target design and the plan for reaching it. Where
[ControlPlane.md](ControlPlane.md) or
[EngineAbstractionCompletion.md](EngineAbstractionCompletion.md) describe
ownership differently, this document wins. Those two describe the code as it is
today and are rewritten when the restructure finishes.

## Layers

| Layer | Owns | Never owns |
| --- | --- | --- |
| Platform UI (SwiftUI on macOS, iOS and iPadOS; WinUI 3 on Windows later) | Views, layout, animation, hover, scroll position, window frames, sidebar width, appearance preferences, presenting the prompts the core asks for, embedding engine views | Browser state, rules, persistence, deciding what happens next |
| `CrestCore` | Every piece of browser state and every rule: Spaces, tabs, folders, splits, history, archive, windows and what each window shows, pages and their live state, preferences, downloads, permissions, credentials policy, import and export, search and completion, onboarding and setup flows, Quick Window and Peek rules, storage, sync | Rendering, input, compositing, engine handles, image bytes, OS services |
| Engine bindings (Chromium in portable C++ with a thin shell per OS; WebKit in Swift) | Creating and closing pages, loading, engine navigation history, find, zoom, capture, printing, DevTools, extensions, network and cookie stores | Deciding browser rules; changing browser state other than by reporting events |
| OS services (supplied by each platform) | CloudKit transport, Keychain, authentication prompts, notification delivery, file pickers, default-browser registration, software updates | Rules; deciding when to save or sync |

Sync stays Apple-only. CloudKit transport is an OS service the Apple hosts
supply through a port, and the core owns records, merging, ordering and
scheduling.

## Two paths, visible in the code

The UI reaches the core and the engines through two objects, and each call
site shows which one it uses.

- **Through the core.** Anything that changes state is an intent object sent
  to the core: `core.send(OpenTab(...), from: window)`. The UI reads state
  only from the core's published model: `core.state`.
- **Direct to the engine.** View work goes straight to the page's engine
  through an `EnginePage`: embedding the view, input, scrolling, zoom, find,
  reload, back and forward, DevTools, printing and capture. `EnginePage` has
  no method that changes browser state. What those actions cause, such as a
  committed navigation, reaches the core as an engine event.

```swift
struct PageCard: View {
    let page: PageState                                // the core's model of this page
    @Environment(CrestCore.self) private var core
    @Environment(Engines.self) private var engines

    var body: some View {
        let enginePage = engines.page(page)            // the page's current engine
        EngineView(enginePage)                          // re-hosts when page.engine changes
            .toolbar {
                Button("Zoom In") { enginePage.zoom(.in) }                               // direct
                Button("Reload") { enginePage.reload() }                                  // direct
                Button("Open in WebKit") { core.send(RehostPage(page, on: .webKit)) }     // through the core
            }
    }
}
```

A search for `core.send(` lists every state change the UI can start. A search
for `EnginePage` lists every direct engine call.

## Modeling rules

1. Everything that crosses a boundary is a named type. Intents (`OpenTab`),
   published changes (`TabOpened`), engine commands (`LoadPage`) and engine
   events (`NavigationCommitted`) are records. Nothing is identified by an
   operation string or a code. The generator gives each type its wire tag, and
   the source never spells one.
2. Rule failures are objects: `TabLimitReached(Limit)`, not `"tab_limit"`.
3. Objects describe themselves. A type owns its data and every behavior that
   depends on it. No sibling `*Codes`, `*Policy`, `*Rules` or `*Mapping` types,
   and no extension files that switch over its kinds. A fixed set is one type
   whose static instances define its members. Each instance is constructed with
   the values that make its behavior emerge: its stored spelling, labels,
   limits, and any rule that differs by kind, passed in as a value or a
   function. Methods are written once over those values and never name a
   particular member, so adding a kind means adding one instance.
   - In C#, this is a sealed class with a private constructor and static
     readonly instances (`TabIconMode.Automatic`, with `Name`, `All` and
     `Named(string)`).
   - In Swift, it is a struct with `static let` instances, which the generator
     emits from the C# instances so the data is written once. A member's wire
     tag is its index in `All`, so `All` only grows at the end.
   - Presentation lives on the instance too. User-facing text is English
     source marked `[Localized]`, with an optional `<Member>Comment` for
     translators, and Swift receives it as a `LocalizedStringResource`, so
     Xcode extracts it into the string catalog. Text that names a number
     spells it `%lld` and names the int member that supplies it, so every
     member shares one catalog key. SF Symbol names are plain strings. Views
     read `phase.title` and `phase.symbol` instead of switching over kinds.
   - A member's data may also be an enum, a flags enum, a record declared
     beside the set, or a list of these; Swift receives each as a literal.
     Every fixed set in the contracts reaches Swift, whether or not a record
     names it.

   A nested `Kinds` enum is used only where a switch cannot be avoided. Plain
   enums remain only for sets whose members carry nothing. Unions of message
   types (changes, events, rejections) are not fixed sets, so the one place
   that handles them switches over them. Capability sets are flags. No
   capability is a string.
4. Identifiers are plain `Guid` in C# and `UUID` in Swift, and they appear only
   at boundaries. Inside the core, methods take the objects themselves
   (`window.Show(space, tab)`), not their identifiers. Crest does not wrap a
   GUID in a type just to name it. The Swift `TabID`, `SpaceID`, `FolderID`,
   `SplitGroupID` and `BrowserWindowID` wrappers retire with the Swift session
   copy.
5. A wrapper type is justified only when it carries behavior or an invariant,
   as `SiteOrigin` does with normalization.
6. The core keeps no JSON in its model. JSON remains only where a stored or
   synced format already requires it, and those formats have hand-written
   codecs. The generator never defines a stored or synced key, because
   renaming a contract field must not rewrite anyone's data.
7. One schema. The C# contract records are the source of truth. The Swift
   models, the C header and the codecs are generated from them, so no model is
   written twice by hand.
8. Every protocol or interface has at least two real implementations, or it
   stands for an OS seam that cannot be faked. The engine contract has two:
   Chromium and WebKit.
9. A change is named for the state it changed and carries the resulting
   values (`TabsChanged`), so a UI never re-applies a rule to work out the
   result. Events the UI reacts to are named for what happened
   (`PageRehosted`).

## The core's model

| Object | Holds | Saved | Synced |
| --- | --- | --- | --- |
| `Session` | Spaces, each with its profile, tabs, folders, splits, history and archive | Yes | Yes, as today |
| `Device` | Windows and what each shows (the Space, and the tab in each Space), split column shares, engine choices per site, device-local preferences | Yes, in the device store | Never |
| `Pages` | Each open page: its tab, its engine, and live state (URL and title before commit, loading, progress, security, media) | Never | Never |
| `Prompts` | Permission, authentication and other questions waiting on the person | Never | Never |
| `Engines` | The registered engine bindings and their capabilities | Never | Never |
| `Downloads`, `Permissions` | The existing ledgers, with the permission records saved as today | As today | Never |

The core publishes typed changes and never resends unchanged state. Changes
caused by an intent come back with the call, so the caller reads the new
state straight away. Changes the core starts itself, such as a finished save,
a sync merge or an engine event, arrive through a wake-up call that the UI
answers by draining the pending batch, at most once per main-queue turn. The
Apple UIs keep a generated read model that they update from those changes, so
reading state never calls into the core. The Windows UI reads the core's
records directly.

Swift and the core always ship in one build, so the binary wire between them
has no versioning. The app checks a schema fingerprint when it creates the
core, so a stale prebuilt core fails at launch instead of misreading data.

The core's model changes on the UI thread. Heavy work, such as a sync merge
or a large import, computes on the core's worker against a snapshot and
commits on the UI thread with a revision check. The core owns the SQLite
schema and transactions, and the host supplies only a directory. Saves run on
the worker after the change is published, except where ordering matters:
sync commits and Space deletion are saved before the intent returns. The core
publishes `Saved(revision)`, so the CloudKit transport stores its server
token only after the merge it covers is on disk.

## Engines

The engine contract is a set of contract records like intents and changes:
commands the core issues (`CreatePage`, `LoadPage`, `ClosePage`,
`ResolvePermission`, …) and events the binding reports (`NavigationCommitted`,
`PageCrashed`, `PermissionRequested`, `ProtectedMediaUnavailable`, …).
`crest_engine.h` carries them in the same generated wire format, and the
generator emits a C++ codec for the Chromium binding. Chromium implements it
in portable C++ and reports events straight to the core, with no Objective-C
or Swift in between. The Mac shell around it handles only view embedding,
popups, menus and web authentication. WebKit implements the same contract in
Swift, once, for macOS and iOS.

Crest can run more than one engine at a time.

- A composition registers a default engine and any others it carries. On the
  Mac, Chromium is the default and WebKit is available. An engine that isn't
  the default starts the first time a page needs it, so it costs nothing until
  then.
- Each page belongs to one engine. Capabilities are read from the page's
  engine, not the app's, so the UI offers Reader on a WebKit page and
  extensions on a Chromium page.
- A Space is one profile on every engine. The profile's Chromium directory and
  its WebKit website data store share the profile's identifier. Deleting the
  Space erases both, and the locked-Space gate covers both.
- `RehostPage` moves a page to another engine. The core closes the page on
  its current engine, creates it on the new one and loads the same URL. The
  page keeps its tab, and the UI re-hosts the view because `page.engine`
  changed.

### Protected media fallback

Crest's Chromium has no Widevine. WebKit plays FairPlay through the system's
own content decryption, so a page whose video needs DRM can move to WebKit.
Crest licenses nothing for this: it uses the platform's WebKit.

1. A page asks for a key system Chromium cannot provide. The Chromium binding
   reports `ProtectedMediaUnavailable(page, keySystem)`.
2. The core picks an engine that supports FairPlay. It does nothing if there
   is none or if the page has already moved once for this reason, so a page
   never bounces between engines.
3. The core rehosts the page and records that this site opens in WebKit on
   this device.
4. The UI shows a notice with an action to move the page back. Later visits
   to the site open in WebKit directly, without the reload.

```csharp
void On(ProtectedMediaUnavailable e)
{
    var page = Pages[e.Page];
    var fallback = Engines.PlayingProtectedMedia(except: page.Engine);
    if (fallback is null || page.WasRehostedFor(RehostReason.ProtectedMedia)) return;

    page.Rehost(fallback, RehostReason.ProtectedMedia);
    Device.EngineChoices.Remember(page.Site, fallback.Kind);
    Changes.Publish(new PageRehosted(page, fallback.Kind, RehostReason.ProtectedMedia));
}
```

These still need proving: which streaming services play in a WebKit page
inside Crest, whether some need Safari's user agent, and where Chromium's
key-system request path gives the cleanest hook for the event.

### Sign-in on a moved page

No cookies or other site data move between engines. A page that moves to
WebKit uses the WebKit website data store of its Space's profile, so the person
signs in there once and that store keeps the sign-in for later visits. Signing
out on one engine does not sign out the other.

## Windows, later

The Windows UI is WinUI 3 in C#, compiled with NativeAOT, with `CrestCore` as
a project reference in the same process. It calls the core directly and
reads its records, with no ABI crossing, serialization or second copy of the
state. As on the Mac, Chromium owns the process and the UI thread, so the
WinUI views mount as XAML Islands in windows the Chromium host creates. A spike
must prove that, along with hosting the page surface, before any Windows work
begins.

## Work packages

Each package moves a live path and deletes the path it replaces in the same
change. Nothing is built beside the app. The earlier message-based kernel was
built beside the app, was never called, and was deleted.

### A. One typed contract

- The contract records, the generator, and the generated Swift models and C
  header.
- A public typed application API: `CrestApp` with intent handlers, queries and
  the change feed.
- The session model becomes typed aggregates instead of JSON trees.
- Operation strings, code tables and hand-written codecs go on both sides.
- Engine capabilities become flags.

Done when no operation string, rule code string or hand-written wire model
remains, and the existing commands run through the typed API.

### B. Change feed, storage and the device store

- The core publishes typed change batches.
- The core owns SQLite and decides what to save and when.
- The device store holds windows and selection, with a one-time migration from
  `BrowserWindowState`.
- The Swift session copy, the per-command rebuild and apply code, the 87
  `persist(` calls and `TransactionalSessionPersistence` go.

Done when Swift holds only the generated read model and durable saves run off
the main thread.

### C. Engine contract and page lifecycle

- `crest_engine.h`, and the core's `Pages` and `Engines`.
- Navigation commit first. It replaces the SwiftUI `.onChange` triggers.
- Then crashes, permissions, downloads, before-unload and residency.
- `crest_chrome_host.mm` splits into portable C++ and a Mac shell. The
  Objective-C bridge and the `CrestRoot` callbacks go.
- One WebKit binding for macOS and iOS. `BrowserPagePool` and
  `MobileBrowserPageStore` shrink to view hosting.
- Live page state moves into `Pages`.

Done when the UI reaches engines only through `EnginePage` and the core, and
both engines report through one event path.

### D. Multiple engines

- Engine registration, per-page engines and `RehostPage`.
- The protected media fallback.
- Per-site engine choices, and capabilities read from each page's engine.

Done when a DRM page on the Chromium product plays after moving to WebKit, and
later visits open there directly.

### E. Remaining app logic

These move into the core:

- import parsers
- command palette ranking and URL completion
- credential CSV and the save flow
- onboarding and setup flows
- the sync controller's state machine
- Quick Window and Peek rules
- the store's remaining rules

The Swift copies of rules the core already has go.

Done when the Swift targets hold only views, the client, engine bindings and
OS services.

### F. Cleanup

- Retire the typed Swift ID wrappers, the hand-written control-plane layer,
  and dead types and flags.
- Remove tests that covered deleted code, following `AGENTS.md`.
- Rewrite `ControlPlane.md` and `EngineAbstractionCompletion.md` to describe
  the finished design.
