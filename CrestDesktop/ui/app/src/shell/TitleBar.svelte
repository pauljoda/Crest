<script lang="ts">
  import type { ShellTransport } from "@crest/core-client";
  import type { Snippet } from "svelte";

  import WindowControls from "./WindowControls.svelte";

  /**
   * The window's title bar where Windows draws windows: the system's title bar
   * is the interface's, so the strip across the top moves the window, holds the
   * page's navigation over the sidebar, and ends in the window's buttons at the
   * top right, flush with the corner as every Windows window's are.
   */
  let { shell, children }: { shell: ShellTransport; children?: Snippet } = $props();
</script>

<header class="title-bar">
  <div class="title-bar-navigation">{@render children?.()}</div>
  <span class="title-bar-drag"></span>
  <WindowControls {shell} />
</header>
