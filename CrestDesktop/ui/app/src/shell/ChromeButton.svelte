<script lang="ts">
  import { motion as tokens } from "@crest/design";

  import { timed } from "../motion";
  import SymbolIcon from "../SymbolIcon.svelte";

  /** One of the window's small symbol buttons. */
  let { symbol, label, onClick, disabled = false, className, size = 16 }: {
    symbol: string;
    label: string;
    /** Hears the click with the button, for a menu that opens below it. */
    onClick?: (button: HTMLButtonElement) => void;
    disabled?: boolean;
    className?: string;
    /** The symbol's box. */
    size?: number;
  } = $props();

  // Pressed, by the pointer or by Return, the button shrinks to 0.9 on the
  // press curve and grows back once let go, from wherever it stands.
  let pressing: Animation | null = null;
  let pressed = false;

  function press(button: HTMLButtonElement, down: boolean) {
    if (pressed === down) return;
    pressed = down;
    const { duration, css } = timed(tokens.press);
    const from = getComputedStyle(button).transform;
    pressing?.cancel();
    pressing = button.animate([{ transform: from === "none" ? "scale(1)" : from }, { transform: down ? "scale(0.9)" : "scale(1)" }],
      { duration, easing: css, fill: down ? "forwards" : "none" });
  }

  function pointerDown(event: PointerEvent & { currentTarget: HTMLButtonElement }) {
    if (disabled || !event.isPrimary || event.button !== 0) return;
    const button = event.currentTarget;
    press(button, true);
    const release = () => {
      removeEventListener("pointerup", release);
      removeEventListener("pointercancel", release);
      press(button, false);
    };
    addEventListener("pointerup", release);
    addEventListener("pointercancel", release);
  }
</script>

<button
  class={className ? `chrome-button ${className}` : "chrome-button"}
  aria-label={label}
  title={label}
  {disabled}
  onclick={(event) => onClick?.(event.currentTarget)}
  onpointerdown={pointerDown}
  onkeydown={(event) => event.key === "Enter" && !disabled && press(event.currentTarget, true)}
  onkeyup={(event) => event.key === "Enter" && press(event.currentTarget, false)}
  onfocusout={(event) => press(event.currentTarget, false)}
>
  <SymbolIcon name={symbol} {size} />
</button>
