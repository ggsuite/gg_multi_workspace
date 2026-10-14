# gg_multi_workspace

Workspace management of the gg_multi tool family - adding repos and
organizations, importing and creating tickets, removing repos and
tickets, syncing the ocean, listing and opening workspaces.

`gg_multi` manages multi-package workspaces and orchestrates editing,
reviewing and publishing across all repos of a ticket. This package
holds the commands that build and maintain those workspaces; the
underlying model lives in `gg_multi_core`.

## Commands

| Command                                     | Purpose                                                                                       |
| ------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `do init workspace`                         | initialise the ocean and instantiate the `dna_gg` DNA in the current directory                |
| `do add <target>`                           | add a repo, `owner/repo`, url, regexp or a whole organisation to the workspace                |
| `do import ticket <path\|url>`              | reproduce a whole ticket from a `ticket.json`                                                 |
| `do create ticket <id>`                     | create `<id>/` in the workspace root with `ticket.json`, `.code-workspace` and `.trash/<id>/` |
| `do create graph`                           | write the dependency graph of the workspace as mermaid or json                                |
| `do rm repo <name…>`                        | delete repos from the current ticket (never from the ocean)                                   |
| `do rm ticket [<id>...]`                    | close tickets: delete remote branches, move the whole folder to `.trash`                      |
| `do upgrade ocean`                          | sync `.ocean` with every registered organisation: clone new repos, trash gone ones            |
| `do code`                                   | open the current ticket in VS Code                                                            |
| `do init claude`                            | aggregate each repo's `CLAUDE.md` into one ticket-level `CLAUDE.md`                           |
| `do exec cmd <cmd>`                         | run a shell command in every ticket repo in dependency order                                  |
| `do localize`                               | localize the references between the ticket repos and commit gg's files                        |
| `do ls repos\|organizations\|deps\|tickets` | list workspace contents with metadata                                                         |

### Localized references

Inside a ticket every repo resolves its sibling repos from their checkouts,
not from the registry. `do add` localizes the whole ticket at its end;
`do localize` does the same without adding anything — run it after adding a
dependency on a sibling repo by hand. Both commit only gg's own files
(`pubspec_overrides.yaml`, `pnpm-workspace.yaml`, lock files, `.gg/`, and
what gg itself wrote during the run) as a `#gg:` commit. Unfinished work —
including the manifest edit that added the dependency — stays uncommitted
and goes into your own commit. `do localize` touches only the repos whose
references are out of sync and reports when there is nothing to do. When a
repo of the ocean lies between two ticket repos but is not in the ticket,
it asks you to run `gg do add <repo>`.

`do add` also takes the ticket's own state into account: the repos lying
between the ticket repos are found in the dependency graph in which the
ticket repos replace their ocean copies, and a dependency only a ticket
repo declares is cloned into the ocean as well.

### Debugging across the repos of a ticket

The `.code-workspace` of a ticket ships a launch configuration
»Debug current vitest file«. It runs the spec file open in the editor with
the vitest of the repo the file belongs to (`${fileWorkspaceFolder}`), so it
works in every folder of the multi-root workspace. Because `gg do add`
links the TypeScript dependencies of the ticket through shims that lead to
the sources of their sibling checkouts (`.gg/ts_links/`, written by
gg_localize_refs), stepping into a dependency lands in its `src/`, and
breakpoints set there hit — in any repo, without configuration. Dart folders
need no counterpart — the Dart extension offers »Run«/»Debug« code lenses by
itself.

### Targets as regular expressions

A `do add` target may be a regular expression selecting repositories the
ocean already holds:

```bash
gg do add "ds_.+"        # every ocean repo whose name starts with ds_
gg do add "gg_one.*"     # gg_one, gg_one_commit, gg_one_core, …
```

The pattern is **anchored** — it has to describe the whole name — so
`gg do add gg` still adds the repository named `gg` and not every name
carrying those two letters. A target matching no ocean repo is used as
before, which is what keeps a url and a repository the ocean does not
hold yet addressable by name. A pattern selecting more than one
repository reports what it expanded to.

Patterns only select what the ocean already has; they discover nothing
on the git platform. Use `--org`, or run `do upgrade ocean` first.

Backend helpers include cloning and branch creation (`git_handler.dart`),
repo setup (`repo_setup.dart`), the add logic
(`add_repository_helper.dart`), `.gitattributes` upkeep
(`git_attributes.dart`), lock-file gitignore handling
(`gitignore_lock_files.dart`), legacy git-hook removal
(`legacy_git_hooks.dart`) and localized-override cleanup
(`dependency_overrides.dart`).

## License

`gg_multi_workspace` is licensed under the terms specified in the
`LICENSE` file.
