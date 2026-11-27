import { createAttachmentKey } from "svelte/attachments";

export { default as Button } from "./Button.svelte";
export { default as Group } from "./Group.svelte";
export { default as Picker } from "./Picker.svelte";
export { default as Row } from "./Row.svelte";
export { default as Segmented } from "./Segmented.svelte";
export { default as Switch } from "./Switch.svelte";
export { default as Toggle } from "./Toggle.svelte";

export interface Choice<T> {
  readonly value: T;
  readonly label: string;
}

/**
 * A page's scroller, which starts where the page was left and remembers where it goes:
 * `<div class="settings-scroll" {...keptScroll(scrolls, key)}>`.
 */
export function keptScroll(scrolls: Map<string, number>, key: string) {
  return {
    [createAttachmentKey()]: (element: HTMLDivElement) => {
      element.scrollTop = scrolls.get(key) ?? 0;
    },
    onscroll: (event: Event & { currentTarget: HTMLDivElement }) => void scrolls.set(key, event.currentTarget.scrollTop),
  };
}
