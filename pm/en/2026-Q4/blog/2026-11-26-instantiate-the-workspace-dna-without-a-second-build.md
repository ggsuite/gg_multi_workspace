<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Instantiate the workspace DNA without a second build

## Motivation

- `gg do init workspace` creates the ocean and places the gg DNA in the
  workspace root: the skills and the managed block of `CLAUDE.md`.
  `gg do create ticket` refreshes that DNA the same way.
- Both ended with "Could not instantiate dna_gg: … git rev-parse
  --show-prefix failed … not a git repository". A new workspace got no DNA
  at all, an existing one stayed on the release it had.
- A workspace gets a stripped-down DNA: only `.claude/` and the block, no
  `doc/`, `scripts/` or `.github/`. The failure came from that stripping.

## Strategy

- Find the failing step by running the helix commands by hand, once with
  the full and once with the stripped-down DNA.
- Remove the step instead of working around its error: it had nothing left
  to do.
- Keep the stripping exactly as it is.
- Let the stand-in for helix in the tests behave like helix, so the step
  cannot come back unnoticed.

## Two steps instead of three

- The DNA was instantiated in a temporary folder with `gg dna init`,
  `gg dna add dna_gg --workspace` and `gg dna build --workspace`.
- `add` builds right after installing the layer. In workspace mode it then
  removes the `dna/` scaffold: a workspace is set up from scratch each
  time, nothing is tracked for a later update.
- The `build` after it therefore found no layer. With the full DNA the
  scaffold stays and the same call passes.
- `instantiateWorkspaceDna` now runs `init` and `add` only. What lands in
  the workspace is the same as before.

## A skill held as a link

- Before the new skills are copied, the skill folders of the earlier DNA
  are removed from `.claude/skills/`.
- A skill the workspace holds as a link was deleted as a file. On macOS and
  Linux that follows the link and fails, on a link to a folder as well as
  on a link to nothing. The instantiation ended with the same "Could not
  instantiate dna_gg".
- The link is now removed as a link. What it points to stays untouched.

## Tests

- The stand-in for the helix commands writes the block and the skills in
  `add` and removes `dna/`, as helix does. A `build` after that throws the
  error helix reports outside a git repository.
- One test names the rule: no `build` after `add`.
- The skill tests cover a file, a link to nothing and a link to a folder
  whose content stays.
- Checked by hand against helix 1.18.0 and dna_gg 1.9.1: an empty folder,
  a workspace with own text in `CLAUDE.md` and own skills, and a temporary
  folder inside a git repository.

## Dependency updates

- helix 1.14.0 → 1.18.0, the constraint is `^1.18.0`.
- Since helix 1.16.0 a managed `CLAUDE.md` block that is already there
  belongs to the DNA even when no layer fills it. A build without layers
  wants to empty it, and outside a git repository it fails on the file it
  would have to overwrite. Up to 1.15 that build was a silent no-op.
- helix 1.15.0 brought `checkDna`, which the placed DNA check
  `test/dna/dna_test.dart` calls.

## Open Points

- An installed gg gets the fix with `dart pub global activate gg`.
- A workspace whose DNA could not be refreshed catches up with the next
  `gg do create ticket` or `gg do init workspace`.
- `gg dna build --workspace`, run by hand in a folder without `dna/`, still
  empties the block. Inside a git repository helix does so without a word.
- `doc/guides/install-guide/install-gg-workspace-guide.md` still names
  three steps. It is generated and follows with the next DNA upgrade.
