<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# gg do add: only the requested repos by default

## Motivation

- `gg do add a c` used to add the repos between `a` and `c` as well
  (`a → b → c`: `b` came along)
- They are needed only when a release **breaks** its dependents — a major
  increment, below 1.0.0 a minor one. Any other release fits the caret
  constraint `b` already has
- Adding them anyway made tickets big: more repos to copy, localize, test
  and release, and a `gg do add` that walks, fetches and clones the whole
  dependency closure before it builds the graph
- Lean tickets were already possible with `--no-transitive` or
  `~/.gg_rc`. They are the default now

## Strategy

- Take the default from the settings: gg_one_core's `GgRc` (re-exported
  by gg_multi_core) now has `do.add.transitive = false`
- Keep every way to get the repos between: `--transitive` for one run,
  `{"do": {"add": {"transitive": true}}}` in `~/.gg_rc` for every run,
  `gg do add transitive for <repo>` exactly when a breaking release needs
  them
- Say in the log why the repos between were left out
- Leave the transitive machinery as it is; it only runs on request now

## The command

- `--transitive`: `defaultsTo: false`, help »Also add the repos between
  the ticket repos (off by default; ~/.gg_rc can turn it on)«
- Precedence unchanged: a flag on the command line, then `~/.gg_rc`, then
  the built-in default
- The skip line names its source:
  - `--no-transitive` when the flag was given
  - `<file>: do.add.transitive = false` when the file sets it
  - `default` otherwise:
    `Skip adding transitive repos (default). A breaking release adds them
    later: gg do add transitive for <repo>.`
- Without `--transitive`, neither the missing dependencies are cloned
  into the ocean nor the dependency graph is built — a plain `gg do add`
  is quicker
- `gg do add transitive [for <repo>…]` and `addReposBetweenWithAddCommand`
  are unchanged: they always add the repos between they are asked for
- Every other construction of `AddCommand` without a settings reader —
  `WorkspaceRepoHost.addWithAddCommand` among them — follows the new
  built-in default too

## Tests

- 21 tests that are about the transitive add itself — the clone passes,
  the graph, the repos between — pass `--transitive` now
- New: the repos between stay out by default and the skip line says
  `default`; `~/.gg_rc` with `"transitive": true` adds them
- A ticket folder without manifest keeps the fallback to the folder name
  covered

## Dependency updates

- gg_one_core: `GgRc.builtInDefaults` leaves `do.add.transitive` off. A
  `~/.gg_rc` that still holds exactly what an older gg wrote — with
  `"transitive": true` — gets the new defaults written into it; an edited
  file is kept. Without that, the new default would not reach anyone who
  ran gg before

## Open Points

- A ticket that releases a breaking version still needs the repos between
  before it is published: `gg do add transitive for <repo>`
