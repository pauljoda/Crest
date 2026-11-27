<script lang="ts" module>
  import type { ShellFrame, ShellTransport } from "@crest/core-client";

  import { reader } from "../reactive";

  const frameReaders = new WeakMap<ShellTransport, () => ShellFrame>();

  /** The window's state as the shell last reported it, followed by the expression that reads it. */
  export function useShellFrame(shell: ShellTransport): ShellFrame {
    let read = frameReaders.get(shell);
    if (!read) {
      read = reader((listener) => shell.subscribeFrame(listener), () => shell.frame);
      frameReaders.set(shell, read);
    }
    return read();
  }

  /**
   * Whether the window has no rounded corner for the page card to follow:
   * maximized or full screen, or a window the shell doesn't frame.
   */
  export function useWindowIsCornerless(shell: ShellTransport | null): boolean {
    if (!shell) return true;
    const frame = useShellFrame(shell);
    return frame.maximized || frame.fullscreen;
  }

  // Windows' own caption glyphs (Segoe Fluent Icons, or Segoe MDL2 Assets
  // before Windows 11), which every window on the system draws its buttons in.
  const glyphs = {
    minimize: "",
    maximize: "",
    restore: "",
    close: "",
  };
</script>

<script lang="ts">
  /**
   * The window's minimize, maximize and close buttons, which the interface
   * draws since the title bar is the interface's; a full-screen window has none.
   */
  let { shell }: { shell: ShellTransport } = $props();

  const frame = $derived(useShellFrame(shell));
</script>

{#if !frame.fullscreen}
  <div class={`window-controls${frame.active ? "" : " inactive"}`}>
    <button class="window-control" aria-label="Minimize" title="Minimize" onclick={() => void shell.window("minimize")}>
      {glyphs.minimize}
    </button>
    <button
      class="window-control"
      aria-label={frame.maximized ? "Restore" : "Maximize"}
      title={frame.maximized ? "Restore Down" : "Maximize"}
      onclick={() => void shell.window("maximize")}
    >
      {frame.maximized ? glyphs.restore : glyphs.maximize}
    </button>
    <button class="window-control close" aria-label="Close" title="Close" onclick={() => void shell.window("requestClose")}>
      {glyphs.close}
    </button>
  </div>
{/if}
