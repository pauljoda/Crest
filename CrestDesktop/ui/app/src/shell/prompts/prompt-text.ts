import type { CoreState, PagePrompt } from "@crest/core-client";
import type { AuthenticationQuestion, DownloadApprovalAsked, PermissionAsked, SiteOrigin } from "@crest/contracts";

const defaultPorts: Readonly<Record<string, number>> = { http: 80, https: 443 };

/**
 * The page's server as a dialog names it: its host, with the port only when
 * it is not the scheme's default, as the Mac's dialogs do.
 */
export function sourceLabel(address: string): string {
  try {
    const url = new URL(address);
    if (!url.hostname) return "Crest";
    return url.port ? `${url.hostname}:${url.port}` : url.hostname;
  } catch {
    return "Crest";
  }
}

/** The server a sign-in is for, named the same way. */
export function authenticationSource(question: AuthenticationQuestion): string {
  const scheme = question.url.split(":", 1)[0].toLowerCase();
  return defaultPorts[scheme] === question.port ? question.host : `${question.host}:${question.port}`;
}

/** A site as the core names it (SiteOrigin.DisplayName). */
export function originName(origin: SiteOrigin): string {
  const base = `${origin.scheme}://${origin.host}`;
  return defaultPorts[origin.scheme] === origin.port ? base : `${base}:${origin.port}`;
}

/** The oldest question about `pageId` that a sheet over the page asks. */
export function sheetPrompt(state: CoreState, pageId: string | null): PagePrompt | null {
  if (!pageId) return null;
  for (const prompt of state.prompts.values()) {
    if (prompt.pageId === pageId && prompt.$kind !== "PermissionAsked") return prompt;
  }
  return null;
}

/** The oldest risky download that waits on the person's approval. */
export function downloadApproval(state: CoreState): DownloadApprovalAsked | null {
  for (const prompt of state.downloadPrompts.values()) {
    if (prompt.$kind === "DownloadApprovalAsked") return prompt;
  }
  return null;
}

/** The oldest permission request about `pageId`, which the address field asks. */
export function permissionPrompt(state: CoreState, pageId: string | null): PermissionAsked | null {
  if (!pageId) return null;
  for (const prompt of state.prompts.values()) {
    if (prompt.pageId === pageId && prompt.$kind === "PermissionAsked") return prompt;
  }
  return null;
}
