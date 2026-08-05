# gg_multi_workspace

Workspace management of the gg_multi tool family - adding repos and
organizations, importing and creating tickets, removing repos and
tickets, syncing the ocean, listing and opening workspaces.

`gg_multi` manages multi-package workspaces and orchestrates editing,
reviewing and publishing across all repos of a ticket. This package
holds the commands that build and maintain those workspaces; the
underlying model lives in `gg_multi_core`.

## Commands

| Command                             | Purpose                                                                                 |
| ----------------------------------- | --------------------------------------------------------------------------------------- |
| `do init workspace`                 | initialise the ocean in the current directory                                            |
| `do add <target>`                   | add a repo, `owner/repo`, url or a whole organisation to the workspace                   |
| `do import ticket <path\|url>`      | reproduce a whole ticket from a `ticket.json`                                            |
| `do create ticket <id>`             | create `tickets/<id>/` with `.ticket` file and `.code-workspace`                         |
| `do create graph`                   | write the dependency graph of the workspace as mermaid or json                           |
| `do rm repo <name…>`                | delete repos from the current ticket (or, with `--from-master`, from the ocean)          |
| `do rm ticket [<id>...]`            | close tickets: delete remote branches, move the whole folder to `.trash`                 |
| `do upgrade ocean`                  | sync `.ocean` with every registered organisation: clone new repos, trash gone ones       |
| `do code`                           | open the current ticket in VS Code                                                       |
| `do init claude`                    | aggregate each repo's `CLAUDE.md` into one ticket-level `CLAUDE.md`                      |
| `do exec cmd <cmd>`                 | run a shell command in every ticket repo in dependency order                             |
| `do ls repos\|organizations\|deps\|tickets` | list workspace contents with metadata                                            |

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
