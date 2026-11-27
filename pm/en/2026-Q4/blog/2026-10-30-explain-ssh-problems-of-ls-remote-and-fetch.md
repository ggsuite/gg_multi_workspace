<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Explain ssh problems of ls-remote and fetch

## Motivation

- A clone already explains an ssh problem and offers to trust an unknown
  host. The other network git calls of the workspace commands did not.
- `remoteExists` decides which organizations own a repository. When ssh
  failed, it answered »no« – the repository looked missing, and the run
  guessed an organization without saying why.
- The fetches of `do add` logged the bare git error, once per call and
  repository.

## Strategy

- Treat `remoteExists` like a clone: offer the unknown host for trust and
  ask git again.
- Explain every other ssh problem with the next step from gg_git's
  `SshHostKeys.setupHint` – once per host, however many calls fail.

## remoteExists

- An unknown host gets the same dialog as a clone: fingerprint, comparison
  with the published one, the question. After a yes, `ls-remote` runs
  again.
- When ssh is not set up for the host, the answer stays false, but the
  next step is logged once per host and run.
- A repository that really does not exist logs nothing, as before.

## The git calls of do add

- `do add` fetches every ocean repository it copies into a ticket:
  `fetch`, `fetch --tags`, `fetch --prune --tags`.
- When one of them fails for ssh, the next step is logged once per host,
  with the url from the repository's `origin`.

## Dependency updates

- gg_git: `Fetch` explains ssh problems in its error, which reaches
  `RepoFreshness` and every other caller of it.

## Open Points

- None.
