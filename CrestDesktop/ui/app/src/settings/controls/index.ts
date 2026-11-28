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
 * A radio group's keys, as Windows moves through one: Tab reaches the chosen
 * option alone (`tabindex` 0 on it, or on the first while none is chosen),
 * and the arrow keys choose and focus the next or previous one, wrapping.
 */
export function radioKeys<T>(choices: readonly { readonly value: T }[], index: number, choose: (value: T) => void) {
  return (event: KeyboardEvent & { currentTarget: HTMLElement }) => {
    const by = event.key === "ArrowRight" || event.key === "ArrowDown" ? 1
      : event.key === "ArrowLeft" || event.key === "ArrowUp" ? -1 : 0;
    if (by === 0 || choices.length === 0) return;
    event.preventDefault();
    const next = (index + by + choices.length) % choices.length;
    choose(choices[next].value);
    event.currentTarget.parentElement?.querySelectorAll<HTMLElement>('[role="radio"]')[next]?.focus();
  };
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
