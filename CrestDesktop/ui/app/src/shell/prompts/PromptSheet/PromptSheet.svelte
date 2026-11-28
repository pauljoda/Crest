<script lang="ts">
  import { AnswerAuthentication, AnswerScriptDialog } from "@crest/contracts";
  import type { PagePrompt } from "@crest/core-client";
  import { motion as tokens } from "@crest/design";

  import type { Session } from "../../../boot";
  import { presence } from "../../../motion";
  import ScriptDialog from "./ScriptDialog.svelte";
  import SignIn from "./SignIn.svelte";

  /**
   * The question a page asks that holds it until the person answers: a script
   * dialog or a server's sign-in, as a sheet over the page card that keeps the
   * page from input meanwhile, as the Mac's sheets keep its window. The core
   * settles each one however it is answered, and the sheet goes with it.
   */
  let { session, prompt, spaceName }: {
    session: Session;
    prompt: PagePrompt | null;
    spaceName: string;
  } = $props();

  // An answered question goes at once; the core's settlement follows.
  let answered = $state<string | null>(null);
  const shown = $derived(prompt && prompt.promptId !== answered && prompt.$kind !== "PermissionAsked" ? prompt : null);
  // Each kind draws its own sheet straight in its backdrop, so the sheet goes with it.
  const dialog = $derived(shown?.$kind === "ScriptDialogAsked" ? shown : null);
  const signIn = $derived(shown?.$kind === "AuthenticationAsked" ? shown : null);
  const settle = (promptId: string, send: () => Promise<unknown>) => {
    answered = promptId;
    void send().catch(() => undefined);
  };
</script>

{#each dialog ? [dialog] : [] as asked (asked.promptId)}
  <div
    class="sheet-backdrop"
    in:presence|global={{ pose: { opacity: 0 }, timing: tokens.surface }}
    out:presence={{ pose: { opacity: 0 }, timing: tokens.surface }}
  >
    <ScriptDialog
      {asked}
      answer={(accepted, text) =>
        settle(asked.promptId, () =>
          session.core.send(AnswerScriptDialog({ promptId: asked.promptId, accepted, text })))}
    />
  </div>
{/each}
{#each signIn ? [signIn] : [] as asked (asked.promptId)}
  <div
    class="sheet-backdrop"
    in:presence|global={{ pose: { opacity: 0 }, timing: tokens.surface }}
    out:presence={{ pose: { opacity: 0 }, timing: tokens.surface }}
  >
    <SignIn
      {asked}
      {spaceName}
      answer={(credential) =>
        settle(asked.promptId, () =>
          session.core.send(AnswerAuthentication({ promptId: asked.promptId, credential })))}
    />
  </div>
{/each}
