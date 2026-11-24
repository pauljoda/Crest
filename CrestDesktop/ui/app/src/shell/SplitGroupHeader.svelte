<script lang="ts" module>
  import type { TabState } from "@crest/contracts";

  /** BrowserSidebarSplitGroupRowMetrics.pointer: the stacked icons draw at a member favicon's size. */
  const glyph = 18;

  /** BrowserSidebarSplitGroupIconDeck: the first three members, the focused one among them and last. */
  function deckMembers(members: readonly TabState[], focusedId: string | null): TabState[] {
    const visible = members.slice(0, 3);
    const focused = members.find((member) => member.id === focusedId);
    if (!focused) return visible;
    if (!visible.includes(focused)) {
      if (visible.length === 0) visible.push(focused);
      else visible[visible.length - 1] = focused;
    }
    return [...visible.filter((member) => member !== focused), focused];
  }
</script>

<script lang="ts">
  import {
    type BrandColor,
    CloseTab,
    CollapseSplit,
    DissolveSplit,
    NameSplit,
    SetSplitIcon,
    type SpaceState,
    type SplitGroupState,
    SplitGroupStateTexts,
    TintSplit,
  } from "@crest/contracts";
  import { motion as tokens } from "@crest/design";

  import type { Session } from "../boot";
  import { showContextMenu } from "../menus";
  import { presence } from "../motion";
  import SymbolIcon from "../SymbolIcon.svelte";
  import DeckCard from "./DeckCard.svelte";
  import { ColorPicker, EmojiPicker, folderDefault, Popover } from "./pickers";
  import { TabIcon } from "./Sidebar";
  import { rowStyle } from "./Sidebar/sidebar-parts.svelte";
  import SplitNameField from "./SplitNameField.svelte";

  /**
   * The Mac's BrowserSidebarSplitGroupHeader: the split's own row, standing as
   * a folder's header does, with its members' icons stacked in the folder
   * symbol's column, or a chevron while it is collapsed, and its title. A click
   * opens or closes the members under it, a double click renames it, and its
   * menu, behind the trailing ellipsis and a right-click alike, names it, gives
   * it an emoji or a colour, separates its tabs or closes them.
   */
  let { session, space, groupId, group, members, focusedId, pagesByTab, depth, onMenu }: {
    session: Session;
    space: SpaceState;
    groupId: string;
    group: SplitGroupState | null;
    members: readonly TabState[];
    focusedId: string | null;
    pagesByTab: ReadonlyMap<string, string>;
    depth: number;
    /** The menu a right-click shows, where the window's selection holds a member: its tabs' own. */
    onMenu?: (event: MouseEvent) => boolean;
  } = $props();

  const title = $derived(group?.displayTitle ?? SplitGroupStateTexts.defaultTitle.text);
  const collapsed = $derived(group?.isCollapsed ?? false);
  let renaming = $state(false);
  let choosing = $state.raw<{ kind: "icon" | "color"; anchor: DOMRect } | null>(null);
  let row: HTMLDivElement | null = null;
  const send = (intent: Parameters<typeof session.core.send>[0]) => void session.core.send(intent).catch(() => {});
  // A split of open tabs closes; one the session keeps does not.
  const canClose = $derived(members.length > 0 && !members[0].placement.isDurable);

  const closeMembers = () => {
    for (const member of members) {
      send(CloseTab({ workspaceId: session.workspaceId, windowId: session.windowId, spaceId: space.id, tabId: member.id, returnTabId: null }));
    }
  };
  const menu = (at: { clientX: number; clientY: number }) => void showContextMenu(session.shell, at, [
    { title: "Rename Split View…", run: () => (renaming = true) },
    { title: "Change Icon…", run: () => row && (choosing = { kind: "icon", anchor: row.getBoundingClientRect() }) },
    { title: "Change Color…", run: () => row && (choosing = { kind: "color", anchor: row.getBoundingClientRect() }) },
    "separator",
    { title: "Separate All Tabs", run: () => send(DissolveSplit({ workspaceId: session.workspaceId, spaceId: space.id, groupId })) },
    ...(canClose ? ["separator" as const, {
      title: "Close Split",
      // Closing the second to last member ends the split; the last is an ordinary tab's close.
      run: closeMembers,
    }] : []),
  ]);

  const commit = (name: string | null) => {
    renaming = false;
    if (name === null) return;
    send(NameSplit({ workspaceId: session.workspaceId, spaceId: space.id, groupId, name: name.trim() || null }));
  };
  const closeChoosing = () => {
    choosing = null;
  };

  // The icon's column shows one of three: the chevron, the split's emoji, or its members' deck.
  const icon = $derived(collapsed ? "chevron" : group?.displayEmojiIcon ? "emoji" : "deck");
  /**
   * The members' icons stacked like cards, at most three, the focused one last
   * and on top: each further back is a little smaller, turned a little about
   * its foot, and lifted a little; the deck slides as focus moves, and the
   * focused icon hops.
   */
  const deck = $derived(deckMembers(members, focusedId));
  const front = $derived(Math.max(deck.length - 1, 0));
</script>

<!-- svelte-ignore a11y_click_events_have_key_events -->
<div bind:this={row} class="sidebar-row folder-row split-header" style={rowStyle(depth, true)}
  role="button" tabindex="0" aria-expanded={!collapsed} aria-label={title}
  {...{ "aria-description": collapsed ? "Expands this Split View" : "Collapses this Split View" }}
  onclick={(event) => {
    if (renaming || event.detail > 1) return;
    send(CollapseSplit({ workspaceId: session.workspaceId, spaceId: space.id, groupId, isCollapsed: !collapsed }));
  }}
  ondblclick={() => (renaming = true)}
  onauxclick={(event) => {
    if (event.button !== 1 || !canClose) return;
    closeMembers();
  }}
  oncontextmenu={(event) => {
    event.preventDefault();
    event.stopPropagation();
    if (onMenu?.(event)) return;
    menu(event);
  }}>
  <!-- The one going leaves the column to the one coming, in its place. -->
  <span class="split-header-icon" aria-hidden="true">
    {#each icon === "chevron" ? ["chevron"] : [] as key (key)}
      <span class="split-chevron" in:presence={{ pose: { opacity: 0, rotate: 90 }, timing: tokens.disclosure }}
        out:presence={{ pose: { opacity: 0, rotate: 90 }, timing: tokens.disclosure, pop: true }}>
        <SymbolIcon name="chevron.right" size={glyph * 0.75} strokeWidth={2.25} />
      </span>
    {/each}
    {#each icon === "emoji" ? [group?.displayEmojiIcon] : [] as emoji ("emoji")}
      <span class="split-emoji" style:font-size="{glyph * 0.9}px" in:presence={{ pose: { opacity: 0 }, timing: tokens.disclosure }}
        out:presence={{ pose: { opacity: 0 }, timing: tokens.disclosure, pop: true }}>{emoji}</span>
    {/each}
    {#each icon === "deck" ? ["deck"] : [] as key (key)}
      <span in:presence={{ pose: { opacity: 0 }, timing: tokens.disclosure }}
        out:presence={{ pose: { opacity: 0 }, timing: tokens.disclosure, pop: true }}>
        <span class="split-deck" style:width="{glyph * 1.45}px" style:height="{glyph}px">
          {#each deck as member, index (member.id)}
            <DeckCard focused={member.id === focusedId} {focusedId} size={glyph}
              style={{
                scale: 1 - (front - index) * 0.055,
                rotate: (index - front) * 3.5,
                x: index * glyph * 0.28,
                y: (front - index) * glyph * 0.045,
                zIndex: index,
              }}>
              <TabIcon {session} tab={member} pageId={pagesByTab.get(member.id) ?? null} size={glyph} />
            </DeckCard>
          {/each}
        </span>
      </span>
    {/each}
  </span>
  {#if renaming}
    <SplitNameField initial={title} onDone={commit} />
  {:else}
    <span class="row-title split-header-title">{title}</span>
  {/if}
  <button type="button" class="split-header-actions" aria-label="Split View actions" title="Split View actions"
    onclick={(event) => {
      event.stopPropagation();
      const bounds = event.currentTarget.getBoundingClientRect();
      menu({ clientX: bounds.left, clientY: bounds.bottom });
    }}>
    <SymbolIcon name="ellipsis" size={14} />
  </button>
  {#if choosing?.kind === "color"}
    <Popover anchor={choosing.anchor} label="Split View Color" onClose={closeChoosing}>
      <ColorPicker title="Split View Color" color={group?.tint ?? folderDefault}
        resetTitle={group?.tint ? "Use Default Color" : null}
        onChoose={(tint: BrandColor) => send(TintSplit({ workspaceId: session.workspaceId, spaceId: space.id, groupId, tint }))}
        onReset={() => send(TintSplit({ workspaceId: session.workspaceId, spaceId: space.id, groupId, tint: null }))} />
    </Popover>
  {/if}
  {#if choosing?.kind === "icon"}
    <Popover anchor={choosing.anchor} label="Split View Icon" onClose={closeChoosing}>
      <EmojiPicker title="Split View Icon" current={group?.displayEmojiIcon ?? null}
        resetTitle={group?.displayEmojiIcon ? "Use Stacked Icons" : null}
        onChoose={(emoji) => {
          send(SetSplitIcon({ workspaceId: session.workspaceId, spaceId: space.id, groupId, emoji }));
          closeChoosing();
        }}
        onReset={() => {
          send(SetSplitIcon({ workspaceId: session.workspaceId, spaceId: space.id, groupId, emoji: null }));
          closeChoosing();
        }} />
    </Popover>
  {/if}
</div>
