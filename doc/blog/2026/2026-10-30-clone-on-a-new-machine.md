<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Clone on a new machine

## Motivation

- On a new machine `gg do add` failed on the first Azure DevOps repo with
  a cryptic error: `PathNotFoundException: Directory listing failed, path
  = '…\.ocean\<org>\<repo>\.git\objects\pack\*'`.
- The real reason was hidden behind it: ssh did not know the host yet
  (»Host key verification failed«). Developers had to clone one repo by
  hand and answer yes before gg worked.
- A first clone should explain itself and, where it is safe, fix itself.

## Strategy

- Make the cleanup of a failed clone harmless, so the git error is always
  what the developer sees.
- Offer to trust an unknown host right in the run, with the fingerprint
  and its comparison against the published one.
- Explain every other ssh problem with the next step instead of a raw
  git error.
- Use gg_git's `SshHostKeys` for everything that is about ssh itself.

## Cleaning up a failed clone

- `do add` clones up to four repos in parallel. The cleanup of a failed
  clone searched the whole new org folder – including the folders of
  clones git was filling or removing right then. A folder vanished while
  it was listed, and that exception replaced the clone error.
- Now only the target folder is searched; its parents are deleted one by
  one while they are empty and never searched.
- A folder that cannot be listed or deleted is left behind: a leftover
  never replaces the clone error.

## Trusting an unknown host

- When the clone fails because the host is unknown, `GitHandler` reads
  the key the host presents and shows its fingerprint – and whether it
  matches the fingerprint GitHub or Azure DevOps publishes.
- It asks whether to add the key to `~/.ssh/known_hosts` and clones again
  on yes. Yes is preselected only when the fingerprint matches.
- A key that differs from the published fingerprint is refused without a
  question: a user who answers yes by habit must not store an attacker's
  key.
- The answer is kept per host and run. Parallel clones of one host wait
  for the one question; dialogs of different hosts come one after
  another. A host that could not be scanned is offered again.
- Whatever goes wrong in the offer is reported and never replaces the
  clone error.

## Explaining ssh problems

- Without a terminal, after a no, for a changed host key or a refused ssh
  key, the clone throws `SshSetupException`: the git error plus the next
  step from `SshHostKeys.setupHint`.
- `addRepositoryHelper` keeps that exception across its organization
  fallbacks, skips the fallback organizations on the same host and throws
  it instead of »Repository not found«.
- `do add` shows it without the generic »probably your SSH key or the
  network« guess.

## Dependency updates

- gg_git: `SshHostKeys` – classifies ssh failures, reads and checks host
  keys, stores trusted ones and says what to do next.

## Open Points

- `remoteExists` and the fetches of `RepoFreshness` still show the bare
  ssh error.
