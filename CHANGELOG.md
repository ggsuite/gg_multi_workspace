# Changelog

## Unreleased

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
