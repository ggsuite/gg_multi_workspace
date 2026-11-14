<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Fetch each ocean repo once per gg do add

## Motivation

- Before `gg do add` copies a repo into the ticket, it brings the ocean
  checkout to the state of its remote: branches, tags and `origin/HEAD`
- That took four connections per repo: `git fetch`,
  `git remote set-head origin --auto`, `git fetch --tags` and
  `git fetch --prune --tags`, with a `git tag -d` of all local tags in
  between
- A repo of the dependency closure was fetched twice in one run: first by
  the refresh of the closure, then again before the copy
- The transitive scan asked pub.dev about every hosted dependency the ocean
  does not hold, one by one. Those are dozens of third-party packages, and
  they are what a run waited for
- GitHub throttles ssh when many repos are touched in a row, so every
  connection that is not opened also is one that cannot be dropped

## Strategy

- Let one fetch bring branches, tags and the default branch
- Remember which ocean repos this run brought up to date and do not fetch
  them again
- Ask pub.dev about all hosted dependencies at once
- Take the number of repos handled at a time from the limit for remote
  work instead of a fixed four
- Install the copied repos side by side where that is safe

## One fetch for branches, tags and default branch

- `_gitFetch` runs one `git fetch --prune --prune-tags --force`. gg_git's
  `Fetch.arguments(mirrorTags: true, followRemoteHead: …)` builds it
- The fetch prunes the branches and tags the remote dropped and moves the
  tags the remote moved. Afterwards the tags are a copy of the remote's
- git ≥ 2.48 updates `origin/HEAD` in the same connection (`GitVersion`
  tells). An older git still gets the `set-head` call afterwards
- `_gitDeleteAllLocalTags`, `_gitFetchTags` and `_gitFetchPruneTags` are
  gone
- The fetch is still retried when the remote drops the connection. The
  retry notice calls it `git fetch`, without the options

## No second fetch within a run

- The refresh of the closure calls gg_multi_core's
  `RepoFreshness.updateAll(mirrorTags: true, onUpToDate: …)`. It fetches
  the tags as well and names every repo that is on its remote state
- `_oceanReposOnRemoteState` keeps the canonical paths of these repos. It
  is cleared when a run starts
- Such a repo is not fetched again before the copy, only reset. The log
  says »<repo> in ocean was fetched by this run already.«

## All pub.dev lookups at once

- `_lookUpHostedDependencies` collects the hosted dependencies of the
  closure and of the ticket repos that are neither known packages nor in
  the cache
- It asks pub.dev for their repository urls, several at a time, and keeps
  the answers in the cache: null for a package pub.dev could not answer for
- The scan then reads the cache and accepts only urls of known
  organizations, as before

## Limits and installs

- Up to `GgParallelism.network` repos are refreshed and copied at a time.
  Each copy starts with a fetch, so the limit is the one for reading from a
  remote
- With `--no-localize` the copied repos are installed through gg_multi_core's
  `installReposDependencies`: several at a time when they resolve from the
  registry only, one after the other as soon as git dependencies are
  involved
- The tests pin the git of `createRunner` to `GitVersion.unknown()`. That
  is the path with the separate `set-head` call, which their process stubs
  can answer

## Open Points

- A git older than 2.48 still opens a second connection per repo for
  `origin/HEAD`
- The command tests run the path of an older git only. The fetch that
  updates `origin/HEAD` by itself is not covered here
- Only the repos the closure refresh brought up to date are remembered. A
  repo outside the closure is fetched once, before its copy
