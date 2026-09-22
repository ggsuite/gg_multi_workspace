# Changelog

## 4.9.2 - 2026-09-22

### Changed

- Run the DNA instantiation of a new workspace quietly

## 4.9.1 - 2026-09-16

### Changed

- Associate DNA configuration files with JSONC in workspaces

## 4.9.0 - 2026-09-15

### Changed

- Also pass --workspace to gg dna add, whose own internal build previously ignored it and instantiated the full package output before the explicit build --workspace step ran

## 4.8.0 - 2026-09-14

### Changed

- `gg do create ticket` fails with an error instead of exit code 0 when the ticket already exists, a legacy `tickets/<id>` included
- `gg do code` fails with an error instead of exit code 0 for a name that is no ticket name

### Fixed

- `gg do rm ticket` and `gg do code` never take a hidden folder such as `.github`, a closed ticket in `.trash` or a root folder without `ticket.json` such as `doc` for a ticket; `gg do code` names such a folder »is no ticket« instead of »not found«
- `gg do create ticket`, `gg do rm ticket`, `gg do code` and `gg do import ticket` (its `issue_id`) refuse every name that is no single visible folder name — empty, a path such as `a/b` or `"$PWD"`, absolute, starting with a dot, or `tickets` in any case — with a message naming the reason; `gg do rm ticket "$PWD"` or `gg do rm ticket ""` no longer move an arbitrary folder, or the whole `tickets` folder of a legacy workspace, to the trash and delete the remote branches named after it. One trailing separator (`T1/` from tab completion) is ignored, and so is the leading `tickets/` a tab completion offers for a legacy ticket: `tickets/L1/` names `L1`, `gg do create ticket tickets/42` creates `42` in the workspace root
- `gg do code` takes `T1//` for the ticket instead of opening the ticket folder as a repo, tolerates repeated and trailing separators in `<ticket>/<repo>` and refuses an absolute path such as `/T1` as such instead of »must not be empty«
- `gg do create ticket` refuses a name the workspace root already holds as a folder or file that is no ticket (`doc`, `dna`, `scripts` after `gg do init workspace`) instead of writing its `ticket.json`, `.code-workspace` and trash folder into it; an empty folder is taken
- `gg do import ticket` creates the ticket folder through the same check, so a `ticket.json` naming `doc` no longer writes into the `doc` folder; an existing ticket of that name is still reproduced again
- The README describes `gg do create ticket` with the ticket folder in the workspace root instead of `tickets/<id>/`

## 4.7.0 - 2026-09-11

### Changed

- `do rm repo` removes the shim gg_localize_refs linked the removed repo through (`.gg/ts_links/<name>`) instead of pruning `tsconfig.workspace.json` paths, which gg_localize_refs 5 no longer writes.

## 4.6.0 - 2026-09-11

### Added

- The `.code-workspace` of a ticket carries a launch configuration »Debug current vitest file« that debugs the open spec with the vitest of the folder it belongs to — together with the source paths gg_localize_refs writes, a test steps into the TypeScript sources of the other ticket repos.

### Changed

- `do rm repo` also drops the removed repo from the source `paths` of `tsconfig.workspace.json` in the repos that stay.

### Fixed

- `gg do add` resets the ocean copy to the repository's default branch instead of `origin/main` and refreshes `origin/HEAD` on fetch; `gg do import ticket` no longer offers the default branch as a ticket branch

## 4.5.0 - 2026-09-11

### Changed

- Rewrite the https://ssh.dev.azure.com:v3 organization base earlier versions recorded to the SSH form git can open

## 4.4.0 - 2026-09-11

### Fixed

- `gg do add` asks the platform's repository list which organization owns a repository, so repositories moved or deleted after `gg do upgrade ocean` are no longer offered under their old organization

## 4.3.1 - 2026-09-10

### Fixed

- Clone Azure DevOps web URLs without a .git suffix, which Azure rejects

## 4.3.0 - 2026-09-09

### Added

- `gg do init workspace` instantiates the latest `dna_gg` in the workspace
folder right after creating the ocean — `gg dna init`, `gg dna add dna_gg`
and `gg dna build` in one go — so the gg guides, skills and the managed
`CLAUDE.md` block are in place before the first ticket.

### Fixed

- Rename the dna_base test fixtures to dna_dart

### Removed

- Remove the stray ticket.json from the repository root

## 4.2.0 - 2026-09-02

### Changed

- Install the dna_ggsuite DNA

## 4.1.2 - 2026-09-02

### Changed

- Use ggwsm in pipelines

### Fixed

- Fix Windows-specific test failures that blocked the review

## 4.1.1 - 2026-08-15

### Changed

- Flutter projecs fail on publish

## 4.1.0 - 2026-08-14

### Changed

- Rework copyright headers

### Fixed

- Cleanup copy right headers. Update to dart 3.13. Auto fixes.
- Cleanup copy right headers. Update to dart 3.13. Auto fixes. Setup quick-check pipeline.

## 4.0.1 - 2026-08-13

### Fixed

- Fix gg do exec

## 4.0.0 - 2026-08-13

### Changed

- Report freshness blockers on a dry run in do upgrade ocean

## 3.1.2 - 2026-08-12

### Changed

- Print an error when invalid dependencies are found in manifest

### Fixed

- Fix package adding algorithm

## 3.1.1 - 2026-08-11

### Changed

- Provide gg via npm
- "First javascript implementation"
- Fix shell changes

## 3.1.0 - 2026-08-10

### Changed

- Refactor commit messages, version increment

## 3.0.0 - 2026-08-10

## 2.3.3 - 2026-08-10

### Fixed

- Various log and color fixes across the gg command output
- Fix org-url repo add, code-workspace upkeep on rm and the auto-merge PR hint
- Various fixes

## 2.3.2 - 2026-08-10

### Fixed

- Fix »gg do rm« issues

## 2.3.1 - 2026-08-10

### Removed

- Merge .ticket with ticket.json. Remove usage of .ticket

## 2.3.0 - 2026-08-10

### Changed

- gg do add --no-transitive

## 2.2.0 - 2026-08-09

### Changed

- Improve commit behavior
- Move gg commit conventions from gg_git to gg_one_core
- Move the git and process plumbing to gg_git
- Record the doCommit state in system commits again

## 2.1.0 - 2026-08-09

## 2.0.0 - 2026-08-08

### Changed

- Allow to pass custom options to exec of dir commands.

## 1.0.1 - 2026-08-05

### Changed

- Make pana work: 1.0.0 changelog headings, examples, shorter description

## 1.0.0 - 2026-08-05

### Added

- Initial boilerplate.

### Changed

- Split gg_multi into multiple packages
