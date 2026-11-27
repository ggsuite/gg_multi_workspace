<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Publish from the workspace root

## Motivation

- `gg do init` writes a CLAUDE.md that lists the gg commands of a ticket
  workspace.
- Its `gg do publish` line made people run the publish inside the ticket
  folder.
- At the end of a publish the ticket folder moves to the trash. Windows
  refuses to move a folder a terminal sits in, so the cleanup failed there
  with "used by another process".

## Strategy

- Show the publish as it works on every platform: from the workspace root,
  with the ticket named by `-i`.
- Say why, so the reader keeps doing it.

## CLAUDE.md commands

- The line now reads `gg do publish -i <ticket>`, to be run by a human from
  the workspace root.
- A sentence below the commands explains that Windows cannot move a folder
  a terminal sits in.

## Result

- Agents and people that follow the generated CLAUDE.md publish from the
  workspace root, and the ticket moves to the trash on Windows too.

## Open Points

- Workspaces initialized before keep their old CLAUDE.md until
  `gg do init` writes it again.
