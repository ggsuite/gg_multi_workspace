<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Resolve only what do add changes

## Motivation

- `gg do add` ended every run by localizing the whole ticket and running
  `pub upgrade` in every ticket repo. `pub upgrade` asks the remote of every
  git dependency for new tags: one ssh connection per git dependency and
  repo.
- Added one by one, N repos cost N·(N+1)/2 upgrades. In a ticket whose
  packages reference each other by git, that added up to minutes per repo.
- On top, every copied repo ran a `pub get` right before the localization
  resolved it again – four copies in parallel, on the same git mirrors of
  the pub cache.

## Strategy

- Resolve with `pub get`. It keeps the lock file and fetches only a locked
  commit the pub cache lacks. Upgrading stays the job of `gg do push`.
- Resolve only the repos that need it, not every ticket repo.
- Install once per repo: the copy installs nothing.
- Keep the run self-healing: what an earlier run left unresolved is
  resolved by the next one.

## The repos a run resolves

- The repos copied in this run – they were never resolved in the ticket.
- The repos a new repo put out of sync: a new sibling changes their
  overrides. A repo moved by the flat-folder migration counts too, its
  override path changed.
- The repos whose dependencies were never installed, or whose resolution
  ignores a path override – a failed or interrupted earlier run.
- All other ticket repos keep their resolution. The closing `#gg:` commit
  still covers every repo, so the config files gg wrote stay committed.

## Installs

- `_copyRepoToTicket` only copies and checks out the ticket branch.
- The closing localization installs the copied repos. With
  `--no-localize`, `do add` installs them one after the other.
- A failed `pub get` or `npm install` is shown also without `--verbose`:
  the repo does not build until it is fixed.

## Result

- Measured with three repos and pub.dev dependencies: one call went from
  250 s to 142 s, three single calls from 394 s to 221 s – both runs of
  the new code still compiled gg from source, about 40 s per call.
- The lock files no longer change on `do add`, so no `#gg:` commit holds
  upgrade noise.

## Dependency updates

- gg_multi_core: `TicketLocalizer.outOfSync` names the repos with
  unlocalized refs, `repoDependenciesOutdated` the ones that must be
  installed again.

## Open Points

- `do commit`, `do push` and `do localize` do not look at outdated
  dependencies yet; they localize the out-of-sync repos only.
