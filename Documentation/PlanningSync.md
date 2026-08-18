# Public planning sync

Crest's public GitHub planning is a one-way view of active release work in
Linear. Linear remains the working source; GitHub Issues, milestones, the
roadmap project, and `Documentation/ROADMAP.md` present the useful public
outcomes.

## Project discovery

An open Linear project enters the public view when it has the `Crest` project
label. Release projects use a `Crest X.Y` or `Crest X.Y.Z` name and map to the
matching GitHub milestone. Milestones are ordered by version, so the earliest
active release remains first when later releases are added.

A Linear project already linked to an open GitHub milestone receives one final
sync even after the Linear project is completed. Closing the GitHub milestone
remains part of the release process rather than an automatic consequence of a
planning status change.

## Issue mapping

Every synced GitHub issue carries a hidden `crest-linear-sync` marker containing
its Linear issue identifier and project identifier. The marker is the durable
identity; titles can change without creating duplicate issues.

| Linear status type | GitHub issue | Project status |
| --- | --- | --- |
| Backlog or unstarted | Open | Backlog |
| Started | Open | In progress |
| Completed | Closed as completed | Done |
| Canceled or duplicate | Closed as not planned | Done |

The `roadmap` label adds an issue to the shared Crest Roadmap project. Platform
and feature labels are derived from the user-facing scope and existing GitHub
labels. The sync preserves unrelated labels, discussion, and manually added
context.

## Public writing boundary

GitHub copy summarizes the user problem, intended outcome, and important
product boundaries in plain language. It does not copy private Linear text
verbatim. Machine paths, branch names, private links, logs, screenshots,
credentials, customer information, internal handoff notes, and implementation
instructions stay out of the public issue.

Issue text changes only when the public outcome changes materially. Status-only
updates should not rewrite otherwise useful discussion.

## Completion evidence

A completed issue links a commit or merged pull request only when there is
direct evidence: the Linear identifier appears in the commit or pull request,
Linear links the change, or the diff unambiguously implements the exact public
outcome. The sync never guesses from dates or similar wording. If evidence is
not available, the issue can close without attribution and gain the link on a
later run.

Commit identifiers are stored in the issue's sync marker. The generated
roadmap displays those links beside completed work.

## Roadmap and release notes

`Scripts/render-roadmap.py --write` rebuilds only the marked section of the
roadmap from open GitHub milestones and `roadmap` issues. Manually maintained
release gates and platform notes remain outside the generated markers.

The same milestone and completion metadata form the release-note handoff. When
a release is approved, release automation can query the closed issues in that
milestone, include their public titles and verified commit links, and combine
them with commit-derived notes. This keeps release copy grounded in delivered
work without making Linear or private planning data part of a public build.
