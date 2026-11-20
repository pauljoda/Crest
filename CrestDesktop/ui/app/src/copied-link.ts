import { LinkToCopy } from "@crest/contracts";
import type { CrestCore } from "@crest/core-client";

/**
 * An address as Crest hands it to another app, as the Mac's BrowserCopiedLink
 * is: only the core's `LinkToCopy` makes one, so every address leaving Crest
 * goes through Super Copy, which strips the trackers its rules name.
 */
export class CopiedLink {
  private constructor(readonly url: string) {}

  /** `url` as Super Copy leaves it. */
  static async of(core: CrestCore, url: string): Promise<CopiedLink> {
    return new CopiedLink(await core.query(LinkToCopy({ url })));
  }

  /**
   * The link as Markdown, labelled `title`, or its host when the title is
   * blank. Brackets in the label and parentheses in the address are escaped,
   * so a Markdown reader neither splits the label nor ends the destination
   * early.
   */
  markdown(title: string): string {
    const label = title.trim();
    const resolved = label || hostOf(this.url) || this.url;
    const escaped = resolved.replaceAll("\\", "\\\\").replaceAll("[", "\\[").replaceAll("]", "\\]");
    const destination = this.url.replaceAll("(", "\\(").replaceAll(")", "\\)");
    return `[${escaped}](${destination})`;
  }
}

function hostOf(url: string): string {
  try {
    return new URL(url).host;
  } catch {
    return "";
  }
}
