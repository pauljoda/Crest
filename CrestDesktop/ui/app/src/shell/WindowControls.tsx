import type { ShellFrame, ShellTransport } from "@crest/core-client";
import { useSyncExternalStore } from "react";

/** The window's state as the shell last reported it. */
export function useShellFrame(shell: ShellTransport): ShellFrame {
  return useSyncExternalStore(
    (listener) => shell.subscribeFrame(listener),
    () => shell.frame,
  );
}

const noFrames = () => () => {};

/**
 * Whether the window has no rounded corner for the page card to follow:
 * maximized or full screen, or a window the shell doesn't frame.
 */
export function useWindowIsCornerless(shell: ShellTransport | null): boolean {
  return useSyncExternalStore(
    (listener) => (shell ? shell.subscribeFrame(listener) : noFrames()),
    () => !shell || shell.frame.maximized || shell.frame.fullscreen,
  );
}

// Windows' own caption glyphs (Segoe Fluent Icons, or Segoe MDL2 Assets
// before Windows 11), which every window on the system draws its buttons in.
const glyphs = {
  minimize: "",
  maximize: "",
  restore: "",
  close: "",
};

/**
 * The window's minimize, maximize and close buttons, which the interface
 * draws since the title bar is the interface's; a full-screen window has none.
 */
export function WindowControls({ shell }: { shell: ShellTransport }) {
  const frame = useShellFrame(shell);
  if (frame.fullscreen) return null;
  return (
    <div className={`window-controls${frame.active ? "" : " inactive"}`}>
      <button className="window-control" aria-label="Minimize" title="Minimize" onClick={() => void shell.window("minimize")}>
        {glyphs.minimize}
      </button>
      <button
        className="window-control"
        aria-label={frame.maximized ? "Restore" : "Maximize"}
        title={frame.maximized ? "Restore Down" : "Maximize"}
        onClick={() => void shell.window("maximize")}
      >
        {frame.maximized ? glyphs.restore : glyphs.maximize}
      </button>
      <button className="window-control close" aria-label="Close" title="Close" onClick={() => void shell.window("requestClose")}>
        {glyphs.close}
      </button>
    </div>
  );
}
