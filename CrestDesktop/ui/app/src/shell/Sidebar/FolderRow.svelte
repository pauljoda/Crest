<script lang="ts">
  import type { FolderState } from "@crest/contracts";

  import { previewHandlers } from "../preview-state.svelte";
  import FolderArtwork from "../FolderArtwork.svelte";
  import { folderItem } from "../sidebar-selection";
  import RenameField from "./RenameField.svelte";
  import { rowStyle } from "./sidebar-parts.svelte";

  /**
   * A folder or group header: a click opens or closes it, as the Mac's does. A
   * folder shows its artwork and, at its end, how many tabs it holds; a group
   * shows only its name, small, semibold and secondary, as a caption over its
   * tabs (the Mac's BrowserGroupHeaderTitle), and no count, as the Mac's
   * defaults have it.
   */
  let {
    folder, tabCount, depth, renaming, marked, held, lifted, insertsBefore, aimedInto, onPress, onToggle, onContextMenu, onRenamed,
  }: {
    folder: FolderState;
    tabCount: number;
    depth: number;
    renaming: boolean;
    /** Whether the row draws itself selected for tab actions, and whether the selection holds it. */
    marked: boolean;
    held: boolean;
    /** Whether a lift carries this folder now. */
    lifted: boolean;
    /** Whether a lift would land just above this row. */
    insertsBefore: boolean;
    /** Whether a lift aims to drop inside this collapsed folder. */
    aimedInto: boolean;
    onPress: (event: PointerEvent & { currentTarget: HTMLElement }) => void;
    onToggle: (event: MouseEvent) => void;
    onContextMenu: (event: MouseEvent) => void;
    onRenamed: (title: string | null) => void;
  } = $props();
</script>

<!-- svelte-ignore a11y_click_events_have_key_events, a11y_role_supports_aria_props -->
<div
  role="button"
  tabindex="0"
  class={`sidebar-row folder-row${folder.isGroup ? " group-row" : ""}${marked ? " unit-selected" : ""}${lifted ? " lifted" : ""}${insertsBefore ? " drop-before" : ""}${aimedInto ? " drop-into" : ""}`}
  style={rowStyle(depth, false)}
  data-row={folder.id}
  data-before-folder={folder.id}
  data-folder={folder.id}
  data-collapsed={String(folder.isCollapsed)}
  data-location={folder.location.name}
  data-unit={folderItem(folder.id)}
  aria-selected={held}
  {...renaming ? {} : previewHandlers(folder.id, "folder")}
  onpointerdown={onPress}
  onclick={renaming ? undefined : onToggle}
  oncontextmenu={onContextMenu}
>
  {#if !folder.isGroup}
    <FolderArtwork symbol={folder.displaySymbol} color={folder.displayColor} expanded={!folder.isCollapsed} />
  {/if}
  {#if renaming}
    <RenameField initial={folder.title} placeholder={folder.isGroup ? "Group Name" : "Folder Name"} onDone={onRenamed} />
  {:else}
    <span class="row-title">{folder.title}</span>
  {/if}
  {#if !folder.isGroup && !renaming}
    <span class="folder-count">{tabCount}</span>
  {/if}
</div>
