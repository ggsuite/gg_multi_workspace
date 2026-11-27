<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Copy the CLAUDE layer files into new tickets

## Motivation

- Every new ticket gets the gg DNA of the workspace root: the managed block
  of `CLAUDE.md`, the skills, the hooks and their settings.
- Since helix 1.14.0 that managed block no longer holds the instructions of
  the DNA layers itself. It only imports them, one line per layer:
  `@.claude/CLAUDE_dna_gg.md`.
- A ticket that received only the block would import files it does not
  have, and Claude Code would start in it without the gg workflow.

## Strategy

- Copy the `.claude/CLAUDE_<layer>.md` files together with the block, so
  every import of the ticket resolves.
- Find the layer files by their name pattern instead of parsing the block:
  helix writes exactly one `CLAUDE_<layer>.md` per layer into `.claude/`.
- Keep the root in step with the build: a layer file the new build no
  longer ships is removed from the root before the build is taken over.
- Leave every other file of `.claude/` alone, the user's own notes
  included.

## Copying the layer files into a ticket

- `claudeLayerFilesIn(dir)` lists the `CLAUDE_*.md` files directly in
  `<dir>/.claude/`, sorted.
- `copyWorkspaceDna` copies them into `<ticket>/.claude/` right after it
  wrote the block into the ticket's `CLAUDE.md`.
- A root without a complete managed block copies no layer file either:
  without the block nothing would import them.

## Keeping the root current

- `_takeOver` deletes the root's layer files that are missing in the
  temporary build, then copies the build's `.claude/` as before.
- A layer that drops out of `dna_gg` therefore does not linger in the root
  and is not copied into later tickets.

## Tests

- New tests cover the copy into a ticket, the root without a block, and a
  root whose layer files are replaced and pruned by a new build.
- The test of the commit failure in `do add` stubbed the process runner
  with `runInShell: true`, which only holds on Windows. It now accepts any
  value, so the suite passes on Linux and macOS as well.

## Dependency updates

- helix ^1.14.0: writes the `CLAUDE.md` of every DNA layer to
  `.claude/CLAUDE_<layer>.md` and lets the managed block import it. The
  regenerated DNA of this repo uses that form, too.

## Open Points

- The markers of the managed block are still copied from helix instead of
  being imported from it.
