// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;

import 'package:gg_multi_workspace/src/backend/add_repository_helper.dart';
import 'package:gg_multi_workspace/src/backend/git_handler.dart';
import 'package:gg_multi_core/gg_multi_core.dart';

/// Brings the ocean in sync with the git platforms.
///
/// Every organization registered in `<root>/.organizations` is asked for its
/// current repository list. A repository the organization has but the ocean
/// workspace lacks is cloned; a repository the ocean holds but the
/// organization no longer offers is moved to `<root>/.trash/.ocean`, never
/// deleted. Tickets are not consulted: a ticket owns its own clone, so
/// removing the ocean copy does not break it.
class UpdateOceanCommand extends Command<void> {
  /// Constructor.
  UpdateOceanCommand({
    required this.ggLog,
    String? rootPath,
    GitHandler? gitCloner,
    GitHubPlatform? gitHubPlatform,
    AzureDevOpsPlatform? azureDevOpsPlatform,
    // coverage:ignore-start
  }) : rootPath = rootPath ?? Directory.current.path,
       gitCloner = gitCloner ?? GitHandler(),
       gitHubPlatform = gitHubPlatform ?? GitHubPlatform(),
       azureDevOpsPlatform = azureDevOpsPlatform ?? AzureDevOpsPlatform() {
    // coverage:ignore-end
    argParser.addFlag(
      'dry-run',
      abbr: 'n',
      negatable: false,
      help: 'Report the changes without applying them',
    );
  }

  // ...........................................................................
  @override
  String get name => 'ocean';

  // ...........................................................................
  /// The former command name, kept as a hidden alias so muscle memory and
  /// scripts using »do upgrade master« keep working.
  @override
  List<String> get aliases => ['master'];

  // ...........................................................................
  @override
  String get description => 'Sync the ocean with the registered organizations';

  /// Log sink.
  final GgLog ggLog;

  /// Directory the command was invoked in.
  final String rootPath;

  /// Clones the repositories that are missing.
  final GitHandler gitCloner;

  /// Lists the repositories of a GitHub organization.
  final GitHubPlatform gitHubPlatform;

  /// Lists the repositories of an Azure DevOps project.
  final AzureDevOpsPlatform azureDevOpsPlatform;

  // ...........................................................................
  @override
  Future<void> run() async {
    final dryRun = argResults!['dry-run'] as bool;
    final oceanPath = WorkspaceUtils.defaultOceanWorkspacePath(
      workingDir: rootPath,
    );
    final root = path.dirname(oceanPath);

    // A workspace created before gg grouped its repositories by organization
    // still holds them flat, which makes them uncomparable to the remote
    // list. Move them first — but not on a dry run, which changes nothing.
    if (!dryRun) {
      migrateToOrgFolders(workspacePath: oceanPath, ggLog: ggLog);
    }

    // `.organizations` lives inside the ocean — that is the path
    // `do add` hands to `addRepositoryHelper`, which maintains the file.
    final organizations = OrganizationUtils.readOrganizations(oceanPath);
    if (organizations.isEmpty) {
      ggLog(
        cAction('No organizations registered. Run ') +
            cCmd('gg do add <org-url>') +
            cAction(' first.'),
      );
      return;
    }

    final fetched = await _fetchAll(organizations);
    if (fetched.isEmpty) {
      return;
    }

    final added = await _addMissing(
      fetched: fetched,
      oceanPath: oceanPath,
      dryRun: dryRun,
    );
    final removed = await _removeOrphans(
      fetched: fetched,
      oceanPath: oceanPath,
      root: root,
      dryRun: dryRun,
    );

    _logSummary(
      added: added,
      removed: removed,
      organizations: fetched.length,
      dryRun: dryRun,
    );
  }

  // ######################
  // Private
  // ######################

  // ...........................................................................
  /// Asks every organization of [organizations] for its repositories.
  ///
  /// An organization whose platform is unknown, or whose CLI is missing or
  /// unauthenticated, is reported and left out of the result — one broken
  /// organization must neither abort the run nor make its repositories look
  /// deleted. The organizations are queried in parallel but reported in
  /// registration order.
  Future<List<_OrgRepos>> _fetchAll(List<Organization> organizations) async {
    final results = List<_OrgRepos?>.filled(organizations.length, null);
    final errors = List<String?>.filled(organizations.length, null);

    await runWithLimit(List<int>.generate(organizations.length, (i) => i), 4, (
      index,
    ) async {
      final org = organizations[index];
      try {
        results[index] = _OrgRepos(org, await _fetchOrg(org));
      } catch (e) {
        errors[index] = e.toString().replaceAll('Exception: ', '');
      }
    });

    for (var i = 0; i < organizations.length; i++) {
      if (errors[i] != null) {
        ggLog(cError('Skipped ${organizations[i].name}: ${errors[i]}'));
      }
    }

    return results.whereType<_OrgRepos>().toList();
  }

  // ...........................................................................
  /// Returns the repositories [org] currently holds.
  Future<List<Repository>> _fetchOrg(Organization org) {
    final platform = const UrlParser().parse(org.url).platformType;
    switch (platform) {
      case 'github':
        return gitHubPlatform.fetchOrgRepos(org.name);
      case 'azure':
        return azureDevOpsPlatform.fetchOrgRepos(
          org.name,
          project: org.projectName,
        );
      default:
        throw Exception(cError('unsupported platform "$platform"'));
    }
  }

  // ...........................................................................
  /// Clones every repository that is offered by an organization but missing
  /// in the ocean. Returns the `<org>/<repo>` names it added.
  ///
  /// A repository is looked up by the identity of its remote url, not by its
  /// folder name: the folder may carry the package name instead, and two
  /// organizations may own a repository of the same name.
  Future<List<String>> _addMissing({
    required List<_OrgRepos> fetched,
    required String oceanPath,
    required bool dryRun,
  }) async {
    final missing = <_OrgRepo>[];
    for (final entry in fetched) {
      for (final repo in entry.repos) {
        final existing = RepoFolderResolver.resolveByRemoteUrl(
          workspacePath: oceanPath,
          repoUrl: repo.cloneUrl,
        );
        if (existing == null) {
          missing.add(_OrgRepo(entry.organization, repo));
        }
      }
    }

    for (final item in missing) {
      ggLog(cDetail('✓ ${dryRun ? 'Would add' : 'Adding'} ${item.label}'));
    }
    if (dryRun || missing.isEmpty) {
      return [for (final item in missing) item.label];
    }

    await runWithLimit(
      missing,
      4,
      (item) => addRepositoryHelper(
        targetArg: item.repository.cloneUrl,
        ggLog: ggLog,
        gitCloner: gitCloner,
        gitHubPlatform: gitHubPlatform,
        azureDevOpsPlatform: azureDevOpsPlatform,
        workspacePath: oceanPath,
        logIfAlreadyAdded: false,
      ),
    );

    return [for (final item in missing) item.label];
  }

  // ...........................................................................
  /// Moves every ocean repository whose organization no longer offers it to
  /// the trash. Returns the `<org>/<repo>` names it removed.
  ///
  /// Only repositories belonging to an organization that answered are
  /// considered — the repositories of an organization that failed to fetch
  /// are untouched, and so is a repository whose remote url is missing or
  /// unparsable: gg cannot tell whether it is gone, so it stays.
  Future<List<String>> _removeOrphans({
    required List<_OrgRepos> fetched,
    required String oceanPath,
    required String root,
    required bool dryRun,
  }) async {
    final removed = <String>[];

    for (final dir in RepoFolderResolver.repoDirs(oceanPath)) {
      final url = RepoFolderResolver.remoteUrl(dir);
      if (url == null) {
        continue;
      }
      final identity = RepoFolderResolver.urlIdentity(url);
      if (identity == null) {
        continue;
      }
      final owner = _ownerOf(url, fetched);
      if (owner == null || owner.identities.contains(identity)) {
        continue;
      }

      final label = RepoFolderResolver.relativePath(
        workspacePath: oceanPath,
        repoDir: dir,
      ).replaceAll(r'\', '/');

      // Moving a repo to the trash removes it from the ocean —
      // worth a warning, not a dimmed detail.
      ggLog(
        dryRun
            ? cDetail('✓ Would move $label to the trash')
            : cDetail('🗑️ Moving $label to the trash'),
      );
      removed.add(label);
      if (dryRun) {
        continue;
      }

      await Trash.moveFromOcean(source: dir, rootPath: root);
      RepoFolderResolver.removeEmptyOrgFolder(
        workspacePath: oceanPath,
        repoDir: dir,
      );
    }

    return removed;
  }

  // ...........................................................................
  /// Returns the fetched organization [url] belongs to, or null when none of
  /// them owns it.
  ///
  /// Azure DevOps groups repositories per project, so an organization that
  /// names a project only owns the repositories of that project — the other
  /// projects of the same account are somebody else's business.
  _OrgRepos? _ownerOf(String url, List<_OrgRepos> fetched) {
    final parsed = const UrlParser().parse(url);
    final org = parsed.org?.toLowerCase();
    if (org == null) {
      return null;
    }
    for (final entry in fetched) {
      if (entry.organization.name.toLowerCase() != org) {
        continue;
      }
      final project = entry.organization.projectName?.toLowerCase();
      if (project != null && parsed.project?.toLowerCase() != project) {
        continue;
      }
      return entry;
    }
    return null;
  }

  // ...........................................................................
  /// Prints what the run did — or, on a dry run, would have done.
  void _logSummary({
    required List<String> added,
    required List<String> removed,
    required int organizations,
    required bool dryRun,
  }) {
    if (added.isEmpty && removed.isEmpty) {
      ggLog(
        darkGray(
          'The ocean is up to date '
          '($organizations organization(s)).',
        ),
      );
      return;
    }
    ggLog(
      darkGray(
        '${dryRun ? 'Would update' : 'Updated'} the ocean: '
        '${added.length} added, ${removed.length} moved to the trash, '
        '$organizations organization(s).',
      ),
    );
  }
}

// .............................................................................
/// An organization together with the repositories it currently offers.
class _OrgRepos {
  /// Constructor.
  _OrgRepos(this.organization, this.repos)
    : identities = {
        for (final repo in repos)
          if (RepoFolderResolver.urlIdentity(repo.cloneUrl) != null)
            RepoFolderResolver.urlIdentity(repo.cloneUrl)!,
      };

  /// The organization.
  final Organization organization;

  /// The repositories it offers.
  final List<Repository> repos;

  /// The `<org>/<repo>` identities of [repos].
  final Set<String> identities;
}

// .............................................................................
/// One repository of one organization.
class _OrgRepo {
  /// Constructor.
  _OrgRepo(this.organization, this.repository);

  /// The organization the repository belongs to.
  final Organization organization;

  /// The repository.
  final Repository repository;

  /// `<org>/<repo>` — how the repository is reported.
  String get label => '${organization.name}/${repository.name}';
}
