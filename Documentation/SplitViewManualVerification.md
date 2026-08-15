# Split View manual verification

Split View is the one 0.4 feature whose contract is mostly geometry, pointer
routing, and live WebKit hosting, so unit tests can prove the arithmetic and the
policies but not the result. This is the ordered checklist that closes that gap:
every item an implementation work package left for a human, in one place, run
once against a release build before the feature ships.

Run every macOS pass against the installed release app, and every mobile pass in
the Simulator or on a device, per the repository's runtime data-safety contract:
set `CREST_ISOLATED_SESSION=1` for every validation launch, never point a pass at
the installed profile, and never repair or clean a real person's Spaces as part
of a run. Sections are ordered so each one builds on the split the previous one
created.

## macOS core

1. Drag a sidebar tab over the page. The lifted row morphs into a webpage card,
   a placeholder opens at the leading, middle, and trailing slot as the pointer
   moves, the existing cards shift to make room, and releasing creates the
   split. The stacked group row appears in the sidebar.
2. The address field tracks the focused card — address text, progress, security
   state, back and forward, reload, and the page menu all describe that card.
   ⌘L edits the focused card's address. ⌘F finds inside the focused card only.
   The focus ring follows clicks.
3. ⌃⌘← and ⌃⌘→ cycle focus through the cards. ⌥⌘U separates all tabs. ⌘W closes
   the focused card and the group survives, dissolving back to a plain tab at
   one member. A member's X in the sidebar does the same thing.
4. Scrolling and two-finger back/forward over an *unfocused* card affect that
   card and do not move focus.
5. Turn on **Focus Follows Mouse in Split View**. Focus moves on hover, and it
   never interrupts address-bar typing — start editing the address, move the
   pointer across cards, and the edit survives.
6. Group row: clicking a member focuses it, **Separate All Tabs** flattens the
   group, and the row drags as a single unit.
7. Resize: the divider respects the minimum card width, widths persist for the
   window and survive relaunch, and a second window keeps independent widths.
8. Memory pressure: no presented card is evicted. Switch to another tab and back
   and every card is restored.
9. Lock a protected Space with a split open. Every card drops instantly.
   Unlocking restores them.
10. Peek and extension popups anchor to the focused card. A Start Page member
    and a navigation-failure member each render inside their own card.

## Drag to split

1. Sidebar boundary: the lifted card paints above the page while it crosses out
   of the sidebar into the content area, with the sidebar docked and floating.
2. Morph anchoring: the row-to-webpage-card morph stays anchored under the
   pointer for the whole crossing.
3. Pinned morph unchanged: lifting a pinned tab still morphs to the pinned tile,
   metric for metric, with no trace of the card shape.
4. Placeholder slots: with a split already open, the placeholder opens before
   the first card, between any two cards, and after the last card, following the
   pointer.
5. Lone tab: with a single tab on show, dragging over the page switches the
   surface into split layout for the drag's duration and offers the slot beside
   that tab.
6. Mid-drag stability: the insertion point does not oscillate while the cards
   shrink to make room for the placeholder — hold the pointer still near a
   boundary and the placeholder stays where it is.
7. Mid-drag hosting: the live webview never re-hosts during the drag. No card
   reloads, blanks, or flickers while the layout latches.
8. Refusals show nothing at all — no placeholder appears for a folder, a whole
   split group, a tab from another Space, a tab already on show, or a group
   already at four members.
9. Two windows: dragging over one window never resolves a card registered by
   the other, and no placeholder appears in the window the pointer is not in.
10. Locked Space: a protected Space that is locked offers no placeholder and
    refuses the drop.
11. Reduce Motion: with Reduce Motion on, the morph and the card shifts settle
    without animation and the drop still commits.

## Link context menu

1. Right-click an ordinary `https` link in the focused card. **Open Link in
   Split View** appears after WebKit's own items, behind a separator. Choosing
   it opens the link as a new focused card beside the page it came from.
2. Right-click plain text. The item is absent.
3. Right-click a link, then right-click plain text. The item is absent the
   second time — a capture never survives into a menu it has nothing to do with.
4. Right-click a link, dismiss the menu without choosing anything, then
   right-click plain text. The item is still absent.
5. Right-click an element nested inside a link — an image or a span inside an
   `<a>`. The item appears and carries the anchor's destination.
6. Right-click an SVG anchor and an image-map `area[href]`. Both resolve against
   their own base document.
7. Right-click a link inside an iframe. The item appears; every frame reports
   for itself.
8. Right-click a `javascript:`, `data:`, `file:`, or `mailto:` link. The item is
   absent.
9. Right-click a link inside a shadow root. The item appears.
10. Right-click a link on a card whose group already holds four members. The
    item is absent.
11. Right-click a link on a pinned tab's page, and on a Start Page. The item is
    absent in both.
12. Repeat scenario 1 in a private window. It appears and works there. Popups
    and extension pages inherit the credential bridge's known shared-controller
    gap and are expected not to offer it.

## iPhone

1. Carousel paging: with a group open, the horizontal toolbar swipe pages
   between cards one at a time and clamps at both ends.
2. Outside a group the toolbar swipe does nothing. Spaces still switch from the
   tab viewer and with ⌥⌘← / ⌥⌘→.
3. The vertical address-capsule swipe still opens the tab viewer, unchanged.
4. The backdrop tracks the focused member as paging settles.
5. Neighbours are pre-built: paging to an adjacent card shows live content
   rather than a blank that loads after arrival.
6. The stacked group row is reachable by touch — each member line keeps a 44pt
   target, a member tap opens the group focused on that member, and long-press
   reaches the group menu (**Separate All Tabs**, **Close Split**) and the
   member menu (**Remove from Split**). Taking a group apart on the phone is
   done from these menus; groups are not drag sources here.

## iPad

1. A split lays out as real resizable columns inside the rounded content
   surface, not as the phone's carousel.
2. Tap-to-focus works on every card, including over live web content that would
   otherwise swallow the tap.
3. A hardware keyboard drives ⌃⌘← / ⌃⌘→ and ⌥⌘U, and all five Split View
   commands appear in the command launcher.
4. Column fractions persist per window and survive relaunch.

## Sync across devices

1. Create a three-tab group on the Mac. The iPhone shows the stacked row; tap
   the middle member and the group opens focused on it.
2. Close members from the sidebar X on one device until the group is two, then
   one, and confirm the other device converges. Break the split up on the Mac
   while it is open on the phone and the phone collapses cleanly to a single
   view with no stolen webview.
3. Partial arrival: with the phone in airplane mode, add a fourth member on the
   Mac, then re-enable networking — the member appears. Kill and relaunch
   mid-sync and no group is dissolved; a lone member waits for its siblings
   rather than being unmade.
