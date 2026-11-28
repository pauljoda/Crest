<script lang="ts">
  import type { AuthenticationAsked } from "@crest/contracts";

  import { authenticationSource } from "../prompt-text";
  import Sheet from "./Sheet.svelte";

  /**
   * A server's request for a user name and password. The credential goes to
   * the engine and nowhere else; this build saves no sign-ins yet, so the sheet
   * offers no saving.
   */
  let { asked, spaceName, answer }: {
    asked: AuthenticationAsked;
    spaceName: string;
    answer: (credential: { username: string; password: string } | null) => void;
  } = $props();

  const question = $derived(asked.question);
  let username = $state("");
  let password = $state("");
  const secure = $derived(question.url.toLowerCase().startsWith("https:"));
  const paragraphs = $derived([
    question.realm ? `Realm: ${question.realm}` : null,
    `This sign-in belongs only to the ${spaceName} Space.`,
    question.previousFailures > 0 ? "The previous credentials were not accepted." : null,
    secure ? null : "Warning: this connection is not protected by HTTPS.",
  ].filter((paragraph): paragraph is string => paragraph !== null));
</script>

<Sheet title="Sign in to {authenticationSource(question)}" primary="Sign In" secondary="Cancel"
  warning={!secure} onPrimary={() => answer({ username, password })} onEscape={() => answer(null)}>
  {#each paragraphs as paragraph (paragraph)}
    <p class="sheet-message">{paragraph}</p>
  {/each}
  <input class="sheet-field" placeholder="Username" aria-label="Username" autocomplete="off"
    bind:value={username} data-autofocus />
  <input class="sheet-field" type="password" placeholder="Password" aria-label="Password" autocomplete="off"
    bind:value={password} />
</Sheet>
