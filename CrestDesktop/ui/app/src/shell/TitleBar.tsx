import type { ShellTransport } from "@crest/core-client";
import type { ReactNode } from "react";

import { WindowControls } from "./WindowControls";

/**
 * The window's title bar where Windows draws windows: the system's title bar
 * is the interface's, so the strip across the top moves the window, holds the
 * page's navigation over the sidebar, and ends in the window's buttons at the
 * top right, flush with the corner as every Windows window's are.
 */
export function TitleBar({ shell, children }: { shell: ShellTransport; children: ReactNode }) {
  return (
    <header className="title-bar">
      <div className="title-bar-navigation">{children}</div>
      <span className="title-bar-drag" />
      <WindowControls shell={shell} />
    </header>
  );
}
