<script lang="ts" module>
  import type { TabState } from "@crest/contracts";

  import type { Session } from "../../boot";
  import type { SelectionItem } from "../sidebar-selection";

  import type { PreviewState } from "../preview-state.svelte";

  interface TabRowProps {
    readonly preview?: PreviewState;
    readonly session: Session;
    readonly tab: TabState;
    readonly pageId: string | null;
    /** Whether the tab is resident without a page: one of Crest's own views holds it, or it is the practice's. */
    readonly resident: boolean;
    readonly depth: number;
    /** Whether the row is a split's member, which its split's card already insets. */
    readonly inSplit: boolean;
    readonly selected: boolean;
    /** Whether the row's title is a field the person is renaming the tab in. */
    readonly renaming: boolean;
    /** The sidebar row this tab is, for a lift's aim; null for a split's member. */
    readonly row: { readonly id: string; readonly aroundTab: boolean } | null;
    /** What a click selects on this row; null for a split's member, whose card is the unit. */
    readonly unit: SelectionItem | null;
    /** Whether the row draws itself selected for tab actions, and whether the selection holds it. */
    readonly marked: boolean;
    readonly held: boolean;
    /** Whether a lift carries this tab now. */
    readonly lifted: boolean;
    /** Whether a lift would land just above this row. */
    readonly insertsBefore: boolean;
    /** Whether a lift aims to make a folder around this tab. */
    readonly aimedAround: boolean;
    readonly onPress: (event: PointerEvent & { currentTarget: HTMLElement }) => void;
    readonly onSelect: (event: MouseEvent) => void;
    readonly onClose: () => void;
    readonly onMiddleClick: () => void;
    readonly onContextMenu: (event: MouseEvent) => void;
    /** The rename ended: with the title to keep, or null when cancelled. */
    readonly onRenamed: (title: string | null) => void;
  }
</script>

<script lang="ts">
  import { tabContentScale } from "../../appearance.svelte";
  import SymbolIcon from "../../SymbolIcon.svelte";
  import { coreState } from "../../use-core";
  import { rowIconSize } from "../sidebar-layout";
  import { previewHandlers } from "../preview-state.svelte";
  import RenameField from "./RenameField.svelte";
  import { rowStyle } from "./sidebar-parts.svelte";
  import TabIcon from "./TabIcon.svelte";

  let {
    session, tab, pageId, resident, depth, inSplit, selected, renaming, row, unit, marked, held, lifted, insertsBefore, aimedAround, onPress,
    preview, onSelect, onClose, onMiddleClick, onContextMenu, onRenamed,
  }: TabRowProps = $props();

  // The surface under the shown tab, which moves between the page's rows (sidebar-parts.svelte.ts).
  // A tab whose page isn't loaded reads dimmer, as the Mac's residency shows it.
  const loaded = $derived(resident || (pageId !== null && coreState(session).pages.get(pageId)?.phase.name === "live"));
</script>

<!-- svelte-ignore a11y_click_events_have_key_events, a11y_role_supports_aria_props -->
<div
  role="button"
  tabindex="0"
  class={`sidebar-row tab-row${selected ? " selected" : ""}${loaded ? "" : " unloaded"}${marked ? " unit-selected" : ""}${lifted ? " lifted" : ""}${insertsBefore ? " drop-before" : ""}${aimedAround ? " drop-nest" : ""}`}
  style={rowStyle(depth, inSplit)}
  data-row={row?.id}
  data-before-tab={row ? tab.id : undefined}
  data-around-tab={row?.aroundTab ? tab.id : undefined}
  data-unit={unit ?? undefined}
  aria-selected={held}
  onpointerdown={onPress}
  onclick={renaming ? undefined : onSelect}
  onauxclick={(event) => event.button === 1 && onMiddleClick()}
  oncontextmenu={onContextMenu}
  {...previewHandlers(tab.id, "tab", preview)}
>
  {#if selected}
    <span class="row-selection"></span>
  {/if}
  <TabIcon {session} {tab} {pageId} size={rowIconSize * tabContentScale()} />
  {#if renaming}
    <RenameField initial={tab.displayTitle} placeholder="Tab Name" onDone={onRenamed} />
  {:else}
    <span class="row-title">{tab.displayTitle}</span>
  {/if}
  <button
    class="row-close"
    aria-label="Close Tab"
    title="Close Tab"
    onclick={(event) => {
      event.stopPropagation();
      onClose();
    }}
  >
    <SymbolIcon name="xmark" size={12} />
  </button>
</div>
