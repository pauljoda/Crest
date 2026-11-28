<script lang="ts">
  import { Sheet } from "../shell/prompts/PromptSheet";
  import type { SpaceDeletionPlan } from "../spaces/space-deletion";

  /**
   * The deletion's question, as the Mac's alert asks it, and for a primary
   * that goes alone, its sheet's choice of the Sub-Space that keeps the group.
   */
  let { plan, onCancel, onDelete }: {
    plan: SpaceDeletionPlan;
    onCancel: () => void;
    onDelete: (successor: string | null) => void;
  } = $props();

  // The chosen Sub-Space while the group still has it, else its first, as the group changes under the sheet.
  let chosen = $state<string | null>(null);
  const successor = $derived(plan.successors.some((candidate) => candidate.id === chosen)
    ? chosen : plan.successors[0]?.id ?? null);
</script>

<Sheet title={plan.title} primary={plan.confirmation} secondary="Cancel" warning destructive
  onPrimary={() => onDelete(successor)} onEscape={onCancel}>
  <p class="sheet-message">{plan.message}</p>
  {#if plan.successors.length > 0}
    <select class="sheet-field sheet-choice" aria-label="New primary" data-testid="space-deletion-successor"
      value={successor ?? ""} onchange={(event) => (chosen = event.currentTarget.value)} data-autofocus>
      {#each plan.successors as candidate (candidate.id)}
        <option value={candidate.id}>{candidate.settings.name}</option>
      {/each}
    </select>
  {/if}
</Sheet>
