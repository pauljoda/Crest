<script lang="ts">
  import { type SiteOrigin, SitePermission, SitePermissionDecision } from "@crest/contracts";

  import type { Session } from "../../boot";
  import { showContextMenu } from "../../menus";
  import SymbolIcon from "../../SymbolIcon.svelte";
  import { decide, permissionTitle, useSiteDecisions } from "../site-control.svelte";

  /**
   * The site's permissions in this Space, as the Mac's disclosure lists them,
   * open where it first appears: each says the choice that answers it, and
   * opens a menu to ask, allow or block.
   */
  let { session, spaceId, origin, expanded, onToggle }: {
    session: Session; spaceId: string; origin: SiteOrigin; expanded: boolean; onToggle: () => void;
  } = $props();

  const decisions = useSiteDecisions(() => ({ session, spaceId, origin }));
  const choose = (event: MouseEvent & { currentTarget: HTMLButtonElement }, permission: SitePermission,
    current: SitePermissionDecision) => {
    const bounds = event.currentTarget.getBoundingClientRect();
    const choice = (title: string, icon: string, decision: SitePermissionDecision) => ({
      title, icon, checked: current === decision, run: () => decide(session.core, spaceId, origin, permission, decision),
    });
    void showContextMenu({ clientX: bounds.left, clientY: bounds.bottom }, [
      choice(permission.askChoiceTitle, "questionmark.circle", SitePermissionDecision.ask),
      // The system asks each time for some capabilities, so nothing allows a site ahead of that question.
      ...(permission.isAskedBySystem ? [] : [choice("Allow", "checkmark.circle", SitePermissionDecision.grantPersistently)]),
      choice("Block", "nosign", SitePermissionDecision.denyPersistently),
    ]);
  };
</script>

<div class="site-permissions">
  <button type="button" class="site-permissions-toggle" aria-expanded={expanded} onclick={onToggle}>
    <span>Permissions</span>
    <SymbolIcon name={expanded ? "chevron.down" : "chevron.right"} size={9} />
  </button>
  {#if expanded}
    {#each SitePermission.all as permission (permission.name)}
      {@const decision = decisions.current?.get(permission.name) ?? SitePermissionDecision.ask}
      <div class="site-permission">
        <span class="site-permission-label">
          <SymbolIcon name={permission.symbol} size={12} />
          {permission.title}
        </span>
        <button type="button" class="site-permission-choice" aria-label="{permission.title}: {permissionTitle(permission, decision)}"
          onclick={(event) => choose(event, permission, decision)}>
          {permissionTitle(permission, decision)}
          <SymbolIcon name="chevron.down" size={8} strokeWidth={3} />
        </button>
      </div>
    {/each}
  {/if}
</div>
