<script lang="ts">
  import { ShortcutModifiers } from "@crest/contracts";
  import { entranceScale, motion as tokens } from "@crest/design";
  import { untrack } from "svelte";
  import type { Attachment } from "svelte/attachments";

  import { portal } from "../../attachments";
  import { type MenuAction, type MenuIcon, type MenuRequest, presentMenusWith, type ShownEntry } from "../../menus";
  import { presence } from "../../motion";
  import { shortcutText } from "../../shortcuts";
  import { SpaceIdentityIcon } from "../../spaces/SpaceIdentity";
  import SymbolIcon from "../../SymbolIcon.svelte";

  /**
   * The window's menus, drawn in the interface on Crest's flyout as the
   * Mac's menus wear the system's: a panel where the person asked for it,
   * kept inside the window, with each submenu beside the row that opens it.
   * While a menu shows, a layer over the window takes every press, so a
   * press elsewhere only closes it, as Windows' own menus do, and the menu
   * takes the keyboard: arrows move through it and into and out of
   * submenus, a letter goes to the next row it starts, Enter chooses and
   * Escape closes the innermost panel.
   */

  /** One open panel: the root, or a submenu opened from a row of the panel before it. */
  interface Level {
    /** Which panel this is, so a submenu opened from another row is placed anew. */
    readonly key: number;
    readonly entries: readonly ShownEntry[];
    /** The row it opened from in the panel before it, or nothing for the root. */
    readonly from: number | null;
    highlighted: number;
  }

  /** How far a panel keeps from the window's edges. */
  const margin = 6;
  /** How long the pointer rests on a row before its submenu opens, or another closes, as Windows waits. */
  const hoverDelay = 180;

  let request = $state<MenuRequest | null>(null);
  let levels = $state<Level[]>([]);
  /** Each open panel's element, by depth, which a submenu places itself beside. */
  let panels: HTMLDivElement[] = [];
  let hoverTimer: ReturnType<typeof setTimeout> | undefined;
  let restoreFocus: HTMLElement | null = null;
  let opened = 0;

  $effect(() => presentMenusWith((next) => {
    untrack(() => {
      if (request) finish(null);
      restoreFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null;
      request = next;
      levels = [{ key: ++opened, entries: next.entries, from: null, highlighted: -1 }];
    });
  }));

  function finish(chosen: MenuAction | null) {
    clearTimeout(hoverTimer);
    const ending = request;
    request = null;
    levels = [];
    restoreFocus?.focus({ preventScroll: true });
    restoreFocus = null;
    ending?.finish(chosen);
  }

  // The menu goes when the window stops being the one in use, or changes size, as a system menu does.
  $effect(() => {
    if (!request) return;
    const close = () => finish(null);
    window.addEventListener("blur", close);
    window.addEventListener("resize", close);
    return () => {
      window.removeEventListener("blur", close);
      window.removeEventListener("resize", close);
    };
  });

  const isRow = (entry: ShownEntry): entry is Exclude<ShownEntry, "separator"> => entry !== "separator";
  const canChoose = (entry: ShownEntry) => isRow(entry) && (entry.enabled ?? true);
  const rowId = (level: number, index: number) => `crest-menu-${level}-${index}`;

  /** The keys beside a row, as Windows writes them; Control combinations are the Mac's alone. */
  function keysText(entry: ShownEntry): string | null {
    if (!isRow(entry) || "submenu" in entry || !entry.keys) return null;
    return entry.keys.modifiers & ShortcutModifiers.Control ? null : shortcutText(entry.keys);
  }

  /**
   * Places panel `depth` inside the window: the root where it was asked for,
   * a submenu beside its row. The panel takes the focus, as it takes the keys.
   * Both wait for the frame after the one that mounts it, before it paints:
   * by then the layer has moved into the window, a move that would take the
   * focus back, and the panel has its size.
   */
  function place(depth: number): Attachment<HTMLDivElement> {
    return (panel) => untrack(() => {
      panels[depth] = panel;
      const origin = request!;
      const from = levels[depth]?.from ?? null;
      const frame = requestAnimationFrame(() => {
        if (panels[depth] === panel && panel.isConnected) arrange(panel, depth, origin, from);
      });
      return () => {
        cancelAnimationFrame(frame);
        if (panels[depth] === panel) panels = panels.slice(0, depth);
      };
    });
  }

  /** Sets panel `depth` where it fits in the window and gives it the focus. */
  function arrange(panel: HTMLDivElement, depth: number, origin: MenuRequest, from: number | null) {
    const width = panel.offsetWidth;
    const room = innerHeight - margin * 2;
    const height = Math.min(panel.scrollHeight, room);
    if (panel.scrollHeight > room) panel.style.maxHeight = `${room}px`;
    let left: number;
    let top: number;
    if (depth === 0 || from === null) {
      left = origin.x + width <= innerWidth - margin ? origin.x : origin.x - width;
      top = origin.y + height <= innerHeight - margin ? origin.y : origin.y - height;
    } else {
      const parent = panels[depth - 1].getBoundingClientRect();
      const row = document.getElementById(rowId(depth - 1, from))!.getBoundingClientRect();
      left = parent.right + width - 3 <= innerWidth - margin ? parent.right - 3 : parent.left - width + 3;
      top = row.top - 5;
    }
    left = Math.max(margin, Math.min(left, innerWidth - width - margin));
    top = Math.max(margin, Math.min(top, innerHeight - height - margin));
    panel.style.left = `${left}px`;
    panel.style.top = `${top}px`;
    if (depth === 0) panel.style.transformOrigin = `${origin.x - left}px ${origin.y - top}px`;
    panel.focus({ preventScroll: true });
  }

  /** Highlights row `index` of panel `depth`, closing any submenu opened deeper than it from another row. */
  function highlight(depth: number, index: number) {
    levels[depth].highlighted = index;
    document.getElementById(rowId(depth, index))?.scrollIntoView({ block: "nearest" });
  }

  function openSubmenu(depth: number, index: number, highlightFirst: boolean) {
    const entry = levels[depth].entries[index];
    if (!isRow(entry) || !("submenu" in entry) || !(entry.enabled ?? true)) return;
    if (levels[depth + 1]?.from === index) {
      if (highlightFirst) highlight(depth + 1, firstChoosable(levels[depth + 1].entries, 1));
      return;
    }
    levels = [...levels.slice(0, depth + 1), {
      key: ++opened, entries: entry.submenu, from: index,
      highlighted: highlightFirst ? firstChoosable(entry.submenu, 1) : -1,
    }];
  }

  /** Closes the submenus deeper than panel `depth`, which takes the focus back with its row still highlighted. */
  function closeDeeper(depth: number) {
    if (levels.length <= depth + 1) return;
    levels = levels.slice(0, depth + 1);
    panels[depth]?.focus({ preventScroll: true });
  }

  function firstChoosable(entries: readonly ShownEntry[], step: 1 | -1, from = step > 0 ? -1 : entries.length): number {
    for (let offset = 1; offset <= entries.length; offset++) {
      const index = (from + step * offset + entries.length * 2) % entries.length;
      if (canChoose(entries[index])) return index;
    }
    return -1;
  }

  function choose(depth: number, index: number) {
    const entry = levels[depth].entries[index];
    if (!canChoose(entry) || !isRow(entry)) return;
    if ("submenu" in entry) openSubmenu(depth, index, true);
    else finish(entry);
  }

  function hover(depth: number, index: number) {
    clearTimeout(hoverTimer);
    highlight(depth, index);
    const entry = levels[depth].entries[index];
    hoverTimer = setTimeout(() => {
      if (isRow(entry) && "submenu" in entry) openSubmenu(depth, index, false);
      else closeDeeper(depth);
    }, hoverDelay);
  }

  /** The menu takes every key while it shows; the innermost panel answers. */
  function keydown(event: KeyboardEvent) {
    if (!request) return;
    event.preventDefault();
    event.stopPropagation();
    // The keys take over from the pointer: a submenu waiting on its rest neither opens nor closes.
    clearTimeout(hoverTimer);
    const depth = levels.length - 1;
    const level = levels[depth];
    switch (event.key) {
      case "ArrowDown": return highlight(depth, firstChoosable(level.entries, 1, level.highlighted));
      case "ArrowUp": return highlight(depth, firstChoosable(level.entries, -1, level.highlighted < 0 ? level.entries.length : level.highlighted));
      case "Home": return highlight(depth, firstChoosable(level.entries, 1));
      case "End": return highlight(depth, firstChoosable(level.entries, -1));
      case "ArrowRight": return level.highlighted >= 0 ? openSubmenu(depth, level.highlighted, true) : undefined;
      case "ArrowLeft": return depth > 0 ? closeDeeper(depth - 1) : undefined;
      case "Escape": return depth > 0 ? closeDeeper(depth - 1) : finish(null);
      case "Tab": return finish(null);
      case "Enter":
      case " ": return level.highlighted >= 0 ? choose(depth, level.highlighted) : undefined;
    }
    if (event.key.length === 1 && !event.ctrlKey && !event.altKey && !event.metaKey) {
      const letter = event.key.toLocaleLowerCase();
      for (let offset = 1; offset <= level.entries.length; offset++) {
        const index = (Math.max(level.highlighted, -1) + offset) % level.entries.length;
        const entry = level.entries[index];
        if (canChoose(entry) && isRow(entry) && entry.title.toLocaleLowerCase().startsWith(letter)) return highlight(depth, index);
      }
    }
  }

  $effect(() => {
    if (!request) return;
    window.addEventListener("keydown", keydown, true);
    return () => window.removeEventListener("keydown", keydown, true);
  });
</script>

{#snippet icon(shown: MenuIcon)}
  <span class="context-menu-icon" aria-hidden="true">
    {#if typeof shown === "string"}
      <SymbolIcon name={shown} size={14} />
    {:else if "tint" in shown}
      <span class="context-menu-tinted" style:color={shown.tint}><SymbolIcon name={shown.symbol} size={14} /></span>
    {:else}
      <SpaceIdentityIcon symbol={shown.space.symbol} branding={shown.space.branding} size={16} />
    {/if}
  </span>
{/snippet}

{#if request}
  <!-- Over Setup while it shows, as Setup lies over the window; last in it, so the title bar's drag area is under it. -->
  <div class="context-menu-layer" role="presentation"
    {@attach portal(() => document.querySelector(".setup-window") ?? document.querySelector(".browser-window") ?? document.body)}
    onpointerdown={(event) => { if (event.target === event.currentTarget) finish(null); }}
    oncontextmenu={(event) => event.preventDefault()}>
    {#each levels as level, depth (level.key)}
      {@const checks = level.entries.some((entry) => isRow(entry) && "checked" in entry && entry.checked !== undefined)}
      <div class={["context-menu", checks && "checks"]} role="menu" tabindex="-1"
        aria-activedescendant={level.highlighted >= 0 ? rowId(depth, level.highlighted) : undefined}
        onpointerleave={() => {
          clearTimeout(hoverTimer);
          if (levels.length === depth + 1) level.highlighted = -1;
        }}
        {@attach place(depth)}
        in:presence={{ pose: depth === 0 ? { opacity: 0, scale: entranceScale } : { opacity: 1 }, timing: tokens.floatingPane }}>
        {#each level.entries as entry, index (index)}
          {#if !isRow(entry)}
            <div class="context-menu-separator" role="separator"></div>
          {:else}
            {@const group = "submenu" in entry}
            {@const enabled = entry.enabled ?? true}
            {@const keys = keysText(entry)}
            <div id={rowId(depth, index)} class={["context-menu-item", index === level.highlighted && "highlighted", !enabled && "disabled"]}
              role={!group && "checked" in entry && entry.checked !== undefined ? "menuitemcheckbox" : "menuitem"}
              aria-checked={!group && "checked" in entry && entry.checked !== undefined ? entry.checked : undefined}
              aria-disabled={!enabled || undefined} aria-haspopup={group ? "menu" : undefined}
              aria-expanded={group ? levels[depth + 1]?.from === index : undefined}
              onpointerenter={() => { if (enabled) hover(depth, index); else { clearTimeout(hoverTimer); level.highlighted = -1; } }}
              onclick={() => choose(depth, index)}>
              {#if checks}
                <span class="context-menu-check" aria-hidden="true">
                  {#if !group && "checked" in entry && entry.checked}<SymbolIcon name="checkmark" size={12} strokeWidth={2.25} />{/if}
                </span>
              {/if}
              {@render icon(entry.icon)}
              <span class="context-menu-title">{entry.title}</span>
              {#if keys}<span class="context-menu-keys">{keys}</span>{/if}
              {#if group}<span class="context-menu-chevron" aria-hidden="true"><SymbolIcon name="chevron.right" size={12} strokeWidth={2} /></span>{/if}
            </div>
          {/if}
        {/each}
      </div>
    {/each}
  </div>
{/if}
