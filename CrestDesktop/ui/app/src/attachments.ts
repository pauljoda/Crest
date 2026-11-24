import type { Attachment } from "svelte/attachments";

/**
 * Moves the element into `target` while it shows, as React's `createPortal`
 * did, for a surface that must stand over everything the window draws:
 * `<div {@attach portal()}>`.
 *
 * The element stands alone in a container of its own there (`display:
 * contents`, so it lays out as the target's child). Svelte removes a block by
 * walking its nodes from the first to the last, so an element moved among
 * the target's own children would walk it into theirs. An element that opens
 * a block must also close it: in-place siblings after it in the same block
 * would be left behind, so give it a block, or a wrapper, of its own.
 */
export function portal(target: () => Element | null = () => document.body): Attachment {
  return (node) => {
    const destination = target();
    if (!destination) return;
    const container = document.createElement("div");
    container.style.display = "contents";
    destination.appendChild(container);
    container.appendChild(node);
    return () => {
      node.remove();
      container.remove();
    };
  };
}
