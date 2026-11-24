<script lang="ts">
  import type { BrandColor, DownloadState } from "@crest/contracts";
  import { motion as tokens } from "@crest/design";
  import { untrack } from "svelte";
  import type { Attachment } from "svelte/attachments";
  import { Tween } from "svelte/motion";

  import type { Session } from "../../boot";
  import { showContextMenu } from "../../menus";
  import { animatePose, timed } from "../../motion";
  import SymbolIcon from "../../SymbolIcon.svelte";
  import { type UtilitySurfaceName, utilitySurfaceOrder, utilitySurfaces } from "../utility-list";
  import { badgeTint, notificationProgress } from "./badges";
  import NotificationBadge from "./NotificationBadge.svelte";

  /**
   * The switcher's page-side accessory, as the Mac's Common Lists button: one
   * control for the archive, history and downloads lists, wearing the symbol of
   * the list it opens, which its menu changes, and badged while downloads have
   * finished unseen, which a press then opens.
   */
  let { session, button = $bindable(null), expanded, chosen, downloads, newDownloads, badgeColor, onToggle, onChoose }: {
    session: Session;
    /** The button while it is on screen, bound for the fan that comes out of it. */
    button?: HTMLButtonElement | null;
    expanded: boolean;
    chosen: UtilitySurfaceName;
    downloads: readonly DownloadState[];
    newDownloads: readonly DownloadState[];
    badgeColor: BrandColor;
    onToggle: () => void;
    onChoose: (surface: UtilitySurfaceName) => void;
  } = $props();

  const opened = $derived(newDownloads.length > 0 ? "downloads" : chosen);
  const state = $derived(expanded ? "Expanded" : "Collapsed");

  // The button gives a little under a press, as Motion's whileTap pressed it.
  const press = timed(tokens.press);
  const pressed = new Tween(1, { duration: press.duration, easing: press.easing });
  const pressStart = (event: PointerEvent) => {
    const primary = event.pointerType === "mouse" ? event.button <= 0 : event.isPrimary !== false;
    if (!primary) return;
    pressed.target = 0.9;
    const release = () => {
      pressed.target = 1;
      removeEventListener("pointerup", release);
      removeEventListener("pointercancel", release);
    };
    addEventListener("pointerup", release);
    addEventListener("pointercancel", release);
  };

  // A download that arrives bounces the symbol, as the Mac's symbol effect does.
  const bounce: Attachment<HTMLElement> = (node) => {
    if (untrack(() => newDownloads.length) === 0) return;
    animatePose(node, { scale: 0.7 }, { scale: 1 }, { type: "spring", visualDuration: 0.35, bounce: 0.5 });
  };
</script>

<button
  bind:this={button}
  class={["chrome-button common-lists-button", expanded && "expanded"]}
  aria-label={utilitySurfaces[opened].title}
  {...{ "aria-description": newDownloads.length > 0 ? `${state}, ${newDownloads.length} new downloads` : state }}
  aria-expanded={expanded}
  title="Archive, History, and Downloads"
  style:transform={pressed.current === 1 ? undefined : `scale(${pressed.current})`}
  onclick={onToggle}
  onpointerdown={pressStart}
  onkeydown={(event) => {
    if (event.key === "Enter" && !event.repeat) pressed.target = 0.9;
  }}
  onkeyup={(event) => {
    if (event.key === "Enter") pressed.target = 1;
  }}
  onblur={() => {
    pressed.target = 1;
  }}
  oncontextmenu={(event) => {
    event.preventDefault();
    void showContextMenu(session.shell, { clientX: event.clientX, clientY: event.clientY }, utilitySurfaceOrder.map((name) => ({
      title: utilitySurfaces[name].title,
      checked: name === chosen,
      run: () => onChoose(name),
    })));
  }}
>
  {#key `${opened}-${newDownloads[0]?.id ?? ""}`}
    <span class="common-lists-symbol" {@attach bounce}>
      <SymbolIcon name={utilitySurfaces[opened].symbol} size={16} strokeWidth={expanded ? 2.25 : 1.75} />
    </span>
  {/key}
  {#if newDownloads.length > 0}
    <NotificationBadge count={newDownloads.length} tint={badgeTint(downloads, badgeColor)} progress={notificationProgress(downloads)} />
  {/if}
</button>
