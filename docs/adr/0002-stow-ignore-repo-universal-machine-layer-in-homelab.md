---
status: accepted
---

# The committed `.stow-local-ignore` holds only repo-universal exclusions; machine/OS layering is the homelab overlay's job

This repo is activated with a single canonical command — `cd ~/dotfiles && stow .` — with
`.stowrc` targeting `~/.config`, so every top-level entry folds into `~/.config/<name>`.
`stow .` links everything except what `.stow-local-ignore` excludes. Two *different* kinds
of thing need excluding, and they had been fused into one file:

- **repo-universal** — repo plumbing that is not app config and must never land in
  `~/.config` on *any* machine: `.beads`, `.claude`, `CLAUDE.md`, `docs`, `.repo-visibility`,
  `.umbel-bundle`, `.worktrees` (collectively, **repo-meta**). Some are tracked (present on
  every checkout); the rest are created at runtime wherever the agent workflow runs.
- **machine/OS-specific** — modules that exist only on one platform, e.g. the Mac-only
  `ghostty`/`karabiner`/`linearmouse`/`ideavimrc`/`nix`/`launchd`, skipped on the Linux devbox.

Because the machine-specific half cannot be committed (it differs per machine), the whole
file had been frozen on devbox with git's `skip-worktree` bit and hand-overlaid with a
Linux-only skip block that was never committed. That freeze is also why the repo-universal
repo-meta exclusions never propagated: a committed change to a `skip-worktree` file never
reaches the working tree stow reads. The reported bug — a plain `stow .` over-linking the 7
repo-meta entries into `~/.config` — and the freeze were the same root cause: two concerns
in one file.

**Decision.** The committed `.stow-local-ignore` is the **single source of truth for
repo-universal exclusions only** — the base plus the repo-meta block — and is tracked
normally. The **machine/OS-specific layer is not the dotfiles repo's concern**: it is applied
externally by the homelab Ansible `overlay` step, which *builds over* the committed file
(reads the committed base, layers the machine/OS delta on top) and sets `skip-worktree` on
devbox so the deploy-managed working-tree copy survives `git pull`. Consequently a repo-meta
addition committed here is **necessary and sufficient**: devbox regenerates
`base + repo-meta + machine-delta` on the next `just devbox-dotfiles`, and non-overlay
machines (a Mac, a fresh checkout) read the committed file directly.

The `skip-worktree` bit on devbox is therefore **deliberate and deploy-owned. Do not remove
it, and do not add a dotfiles-repo machine layer** (e.g. `~/.stowrc`, `--ignore` in `.stowrc`,
or per-package `stow pkg…`) **to "fix" the frozen file** — that would duplicate or fight the
overlay and break the single `stow .` flow.

## Considered options

- **A per-machine `~/.stowrc` layer in the dotfiles repo** (`--ignore=^ghostty$` … in `$HOME`,
  which stow appends to the local-ignore list) — rejected: it reinvents a machine layer the
  homelab overlay already owns, splitting machine state across two systems. It *does* work
  (stow reads `~/.stowrc`, and `--ignore` stacks on top of `.stow-local-ignore` rather than
  replacing it — both verified), which is exactly why it was tempting.
- **Explicit package selection** (`stow atuin bat git …` per machine) — rejected: breaks the
  single `stow .` flow that ADR 0001 treats as an invariant, and pushes the machine list into
  an unversioned command.
- **Drop the machine skips and accept the Linux clutter** — rejected: the skips are
  deliberate, and `nix` in particular could collide with a real `~/.config/nix` on a Linux
  host that uses Nix.
- **Commit repo-meta to the base but keep `skip-worktree` + a hand-synced machine block** (the
  original bead's option) — rejected: condemns every machine to a manual two-layer re-sync for
  every future universal exclusion. Dissolved once the overlay was reworked to build over the
  committed file.
- **Duplicate the repo-meta list into the overlay source** — rejected: the overlay consumes
  the committed file, so a second copy would only drift. The homelab change was structural
  (stop clobbering the committed file), not a copied list.

## Consequences

- Adding or removing a repo-universal exclusion is a one-line commit to `.stow-local-ignore`;
  it reaches every machine (devbox via the overlay's next deploy, others directly). No
  per-machine step.
- The dotfiles repo never encodes machine/OS conditionals; that knowledge lives entirely in
  the homelab overlay. The two repos are coupled by one contract: *the committed
  `.stow-local-ignore` is the repo-universal base the overlay builds on.*
- `git status` on devbox stays clean despite the working-tree file differing from HEAD — an
  expected effect of the deploy-set `skip-worktree` bit, not drift to be corrected.
- Repo-meta entries are written as anchored, dot-escaped regexes (`^\.beads$`, `^CLAUDE\.md$`,
  …), consistent with the existing `^ghostty$` style and safe against substring/wildcard
  over-matching.
