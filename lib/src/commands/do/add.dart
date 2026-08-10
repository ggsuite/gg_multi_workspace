// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
// ignore: lines_longer_than_80_chars
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_localize_refs/gg_localize_refs.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_one/gg_one.dart' as gg;
import 'package:gg_process/gg_process.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as path;
import 'package:pubspec_parse/pubspec_parse.dart';

import 'package:gg_multi_workspace/src/backend/add_repository_helper.dart';
import 'package:gg_multi_workspace/src/backend/dependency_repo_url.dart';
import 'package:gg_multi_core/gg_multi_core.dart';
import 'package:gg_multi_workspace/src/backend/git_attributes.dart';
import 'package:gg_multi_workspace/src/backend/git_handler.dart';
import 'package:gg_multi_workspace/src/backend/gitignore_lock_files.dart';
import 'package:gg_multi_workspace/src/backend/legacy_git_hooks.dart';
import 'package:gg_multi_workspace/src/backend/repo_setup.dart';

/// Resolves the repository URL of a hosted dependency.
/// Subset of [fetchDependencyRepoUrl] without named args, for test stubs.
typedef FetchRepoUrl = Future<String?> Function(String packageName);

/// Command to add a repo or all repos of an organization to ocean+ticket.
/// In ticket mode it also auto-clones transitive deps and re-localizes refs.
/// Use `--force` to overwrite an existing repo in the ocean.
/// `--organization` may be given multiple times to add all repos of several
/// organization folders of the ocean at once. `--no-localize`
/// copies the repos without rewriting their references to local paths.
class AddCommand extends Command<dynamic> {
  /// Constructor for AddCommand.
  AddCommand({
    required this.ggLog,
    GitHandler? gitCloner,
    GitHubPlatform? gitHubPlatform,
    ProcessRunner? processRunner,
    String? oceanWorkspacePath,
    String? executionPath,
    gg.DoCommit? ggDoCommit,
    SortedProcessingList? sortedProcessingList,
    ChangeRefsToPubDev? unlocalizeRefs,
    ChangeRefsToLocal? localizeRefs,
    BackupPublishTo? backupPublishTo,
    Graph? graph,
    FetchRepoUrl? fetchRepoUrl,
    SelectOrganization? selectOrganization,
    // coverage:ignore-start
  }) : _selectOrganization = selectOrganization ?? defaultSelectOrganization,
       gitCloner = gitCloner ?? GitHandler(),
       gitHubPlatform = gitHubPlatform ?? GitHubPlatform(),
       processRunner = processRunner ?? ggRunProcess,
       executionPath = executionPath ?? Directory.current.path,
       oceanWorkspacePath =
           oceanWorkspacePath ?? WorkspaceUtils.defaultOceanWorkspacePath(),
       _ggDoCommit = ggDoCommit ?? gg.DoCommit(ggLog: ggLog),
       _sortedProcessingList =
           sortedProcessingList ?? SortedProcessingList(ggLog: ggLog),
       _unlocalizeRefs = unlocalizeRefs ?? ChangeRefsToPubDev(ggLog: ggLog),
       _localizeRefs = localizeRefs ?? ChangeRefsToLocal(ggLog: ggLog),
       _backupPublishTo = backupPublishTo ?? BackupPublishTo(ggLog: ggLog),
       _graph = graph ?? Graph(ggLog: ggLog),
       _fetchRepoUrl = fetchRepoUrl ?? fetchDependencyRepoUrl
  // coverage:ignore-end
  {
    argParser.addFlag(
      'force',
      abbr: 'f',
      help: 'Overwrite existing repository in ocean.',
      defaultsTo: false,
    );
    argParser.addFlag(
      'verbose',
      abbr: 'v',
      help: 'Enable verbose logging.',
      defaultsTo: false,
    );
    argParser.addFlag(
      'localize',
      help: 'Localize the refs after copying (default)',
      defaultsTo: true,
      negatable: true,
    );
    argParser.addMultiOption(
      'org',
      help: 'Add all repos of an ocean organization folder',
    );
    argParser.addFlag(
      'all',
      help: 'Add all repositories of the ocean to the ticket.',
      defaultsTo: false,
      negatable: false,
    );
  }

  /// The log function.
  final GgLog ggLog;

  /// Instance to handle cloning.
  final GitHandler gitCloner;

  /// Optional GitHub platform instance to handle GitHub-specific operations.
  final GitHubPlatform? gitHubPlatform;

  /// Instance to handle running general processes.
  final ProcessRunner processRunner;

  /// Resolved ocean path.
  final String oceanWorkspacePath;

  /// The path from which the command was executed.
  final String executionPath;

  /// gg do commit used after localization with --git in ticket copies.
  final gg.DoCommit _ggDoCommit;

  /// Sorted processing helper for ticket-wide iteration.
  final SortedProcessingList _sortedProcessingList;

  /// Unlocalize refs helper.
  final ChangeRefsToPubDev _unlocalizeRefs;

  /// Localize refs helper.
  final ChangeRefsToLocal _localizeRefs;

  /// Captures original `publish_to` so it can be restored on publish.
  final BackupPublishTo _backupPublishTo;

  /// Graph helper for determining nodes between endpoints.
  final Graph _graph;

  /// Resolves a hosted-dep repo URL; tests inject stubs (incl. throwing).
  final FetchRepoUrl _fetchRepoUrl;

  /// Asks which organization a plain repo name refers to when several own it.
  final SelectOrganization _selectOrganization;

  @override
  String get name => 'add';

  @override
  String get description => 'Add a repo or a whole organization to the ticket';

  @override
  Future<void> run() async {
    ggLog(cDetail('\n✓ Copying repos'));

    final targets = argResults!.rest;
    final bool force = argResults!['force'] as bool;
    final String? ticketPath = WorkspaceUtils.detectTicketPath(executionPath);
    final bool verbose = argResults!['verbose'] as bool? ?? false;
    final bool localize = argResults!['localize'] as bool? ?? true;
    final orgs = argResults!['org'] as List<String>;
    final bool all = argResults!['all'] as bool;

    if (targets.isEmpty && !all && orgs.isEmpty) {
      throw UsageException('Missing target parameter.', usage);
    }

    // Both options take their repositories from the ocean and
    // copy them into a ticket, so outside of one there is nothing to do.
    if (ticketPath == null && (all || orgs.isNotEmpty)) {
      throw UsageException(
        '--all and --org can only be used from inside a ticket workspace.',
        usage,
      );
    }

    // Maintenance: a workspace created before gg grouped its repositories by
    // organization still holds them flat. Move them first, so everything
    // below sees a single layout.
    migrateToOrgFolders(workspacePath: oceanWorkspacePath, ggLog: ggLog);
    if (ticketPath != null) {
      // The ticket is re-localized at the end of this run, which repairs the
      // relative path references the move invalidates.
      migrateToOrgFolders(workspacePath: ticketPath, ggLog: ggLog);
    }

    // If not in a ticket workspace: keep original behaviour (no graph logic).
    if (ticketPath == null) {
      await runWithLimit(
        targets,
        4,
        (targetArg) => addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: gitCloner,
          gitHubPlatform: gitHubPlatform,
          workspacePath: oceanWorkspacePath,
          force: force,
          logIfAlreadyAdded: true,
          selectOrganization: _selectOrganization,
        ),
      );
      return;
    }

    // Ticket mode: ensure requested repos are present in ocean first.
    final requestedRepoNames = <String>{};
    for (final targetArg in targets) {
      final repoName = extractRepoName(targetArg);
      if (repoName != null) {
        requestedRepoNames.add(repoName);
      }
    }

    // --all and --org name repos that are already in the ocean, so
    // they join the requested ones after the cloning step below.
    if (all) {
      requestedRepoNames.addAll(_allOceanRepoNames());
    }
    if (orgs.isNotEmpty) {
      requestedRepoNames.addAll(_oceanRepoNamesOfOrgs(orgs));
    }

    if (requestedRepoNames.isEmpty) {
      ggLog(cWarn('No repositories to add.'));
      return;
    }

    await runWithLimit(
      targets,
      4,
      (targetArg) => addRepositoryHelper(
        targetArg: targetArg,
        ggLog: ggLog,
        gitCloner: gitCloner,
        gitHubPlatform: gitHubPlatform,
        workspacePath: oceanWorkspacePath,
        force: force,
        // When inside a ticket we do not spam "already added" messages.
        logIfAlreadyAdded: false,
        selectOrganization: _selectOrganization,
        // We intentionally do not copy here; we copy after graph processing.
      ),
    );

    // Clone missing transitive deps so the graph can resolve between-nodes.
    await _cloneMissingTransitiveDeps(ggLog: ggLog);

    final ticketDir = Directory(ticketPath);

    // Build dep graph of ocean + compute nodes between endpoints.
    Map<String, Node> allNodes = const {};
    try {
      allNodes = await _graph.get(
        directory: Directory(oceanWorkspacePath),
        ggLog: ggLog,
      );
    } catch (e) {
      ggLog(cError('Failed to build dependency graph: $e'));
      allNodes = const {};
    }

    // Endpoints = CLI-requested repos + repos already in the ticket.
    final endpointsByName = <String, Node>{};

    // Endpoints based on requested repositories ------------------------------
    for (final name in requestedRepoNames) {
      final node = findNode(packageName: name, nodes: allNodes);
      if (node != null) {
        endpointsByName.putIfAbsent(node.name, () => node);
      }
    }

    // Additional endpoints from existing ticket repositories -----------------
    final existingTicketRepos = RepoFolderResolver.repoDirs(ticketPath);

    for (final repoDir in existingTicketRepos) {
      final repoName =
          RepoFolderResolver.packageName(repoDir) ??
          path.basename(repoDir.path);
      final node = findNode(packageName: repoName, nodes: allNodes);
      if (node != null) {
        endpointsByName.putIfAbsent(node.name, () => node);
      }
    }

    final endpoints = endpointsByName.values.toList();

    final betweenNodes = endpoints.length >= 2
        ? _graph.getNodesBetween(allNodes, endpoints)
        : <Node>[];

    final finalToCopy = <String>{
      ...requestedRepoNames,
      // Use the directory name, not the (primary) package name: for a
      // cross-language bridge repo the Dart package name differs from the
      // folder name, and the copy step locates repos by folder name.
      ...betweenNodes.map((n) => path.basename(n.directory.path)),
    };

    final GgLog taskLog = verbose ? ggLog : <String>[].add;

    await _copyReposToTicket(
      ticketPath: ticketPath,
      repoNames: finalToCopy,
      ggLog: taskLog,
      reportLog: ggLog,
    );

    // Write config files (workspace, .gitattributes) before commit.
    await GgStatusPrinter<void>(
      message: 'Writing project config files',
      ggLog: ggLog,
      dark: true,
    ).run(() => _writeProjectConfigFiles(ticketDir: ticketDir, ggLog: taskLog));

    // Finally perform a single re-localization pass for the whole ticket.
    if (localize) {
      await GgStatusPrinter<void>(
        message: 'Localize dependencies',
        ggLog: ggLog,
        dark: true,
      ).run(
        () => _relocalizeAllReposInTicket(ticketDir: ticketDir, ggLog: taskLog),
      );
    } else {
      // Without localization the ticket description is still kept current — it
      // describes which repos the ticket holds, not how they reference another.
      await _writeTicketJson(ticketDir: ticketDir, ggLog: taskLog);
      ggLog(cDetail('Skip localizing references (--no-localize).'));
    }

    ggLog(cDetail('✔ Successfully added repos'));
  }

  /// Folder names of all repositories of the ocean.
  Set<String> _allOceanRepoNames() => <String>{
    for (final repoDir in RepoFolderResolver.repoDirs(oceanWorkspacePath))
      path.basename(repoDir.path),
  };

  /// Folder names of the repositories that sit in one of the `<ocean>/<org>`
  /// folders named in [orgs]. Repositories that still lie flat in the ocean
  /// workspace belong to no organization folder and are never returned.
  Set<String> _oceanRepoNamesOfOrgs(List<String> orgs) {
    final result = <String>{};

    for (final org in orgs) {
      final namesOfOrg = <String>{};

      for (final repoDir in RepoFolderResolver.repoDirs(oceanWorkspacePath)) {
        final segments = path.split(
          RepoFolderResolver.relativePath(
            workspacePath: oceanWorkspacePath,
            repoDir: repoDir,
          ),
        );
        if (segments.length < 2) {
          continue;
        }
        if (segments.first.toLowerCase() == org.toLowerCase()) {
          namesOfOrg.add(segments.last);
        }
      }

      // A typo in the organization name would otherwise silently add nothing.
      if (namesOfOrg.isEmpty) {
        ggLog(
          cWarn(
            'No repositories found for organization $org '
            'in the ocean.',
          ),
        );
      }
      result.addAll(namesOfOrg);
    }

    return result;
  }

  // Ticket support helpers
  // ...........................................................................
  /// Clones missing deps of every repo in ocean that belongs to a known org.
  /// Git deps go via [addRepositoryHelper]; hosted deps via pub.dev lookup.
  /// Loops to a fixpoint; failures are swallowed (helper already logs).
  Future<void> _cloneMissingTransitiveDeps({required GgLog ggLog}) async {
    final oceanDir = Directory(oceanWorkspacePath);
    if (!oceanDir.existsSync()) {
      return;
    }

    // Normalize known org URLs once (e.g. "https://github.com/ggsuite").
    final orgs = OrganizationUtils.readOrganizations(oceanWorkspacePath);
    final orgUrls = orgs
        .map((o) => o.url.replaceAll(RegExp(r'/+$'), '').toLowerCase())
        .toSet();

    // Known org names, used to map npm scopes (`@<org>/<name>`) back to a
    // cloneable repository in a known organization.
    final orgNames = orgs.map((o) => o.name.toLowerCase()).toSet();

    // Cache pub.dev lookups across the fixpoint loop.
    final hostedLookupCache = <String, String?>{};

    while (true) {
      final existingDirs = RepoFolderResolver.repoDirs(oceanWorkspacePath);

      // Known names: folder basenames plus manifest package names, so that
      // a cross-language bridge repo (whose folder name differs from its
      // package name) is recognized by its package name too.
      final knownPackages = <String>{};
      for (final dir in existingDirs) {
        knownPackages.add(path.basename(dir.path));
        final packageName = RepoFolderResolver.packageName(dir);
        if (packageName != null) {
          knownPackages.add(packageName);
        }
      }

      // Plan: depName -> targetArg (name for git, full URL for hosted).
      final plan = <String, String>{};

      for (final repoDir in existingDirs) {
        Future<void> scan(Map<String, Dependency> deps) async {
          for (final entry in deps.entries) {
            final depName = entry.key;
            if (knownPackages.contains(depName) || plan.containsKey(depName)) {
              continue;
            }
            final dep = entry.value;
            if (dep is GitDependency) {
              plan[depName] = depName; // helper falls back to org URLs
            } else if (dep is HostedDependency) {
              // Resolve repo URL via pub.dev; accept only known-org URLs.
              if (!hostedLookupCache.containsKey(depName)) {
                try {
                  hostedLookupCache[depName] = await _fetchRepoUrl(depName);
                } catch (_) {
                  hostedLookupCache[depName] = null;
                }
              }
              final repoUrl = hostedLookupCache[depName];
              if (repoUrl == null || repoUrl.isEmpty) {
                continue;
              }
              final normalized = repoUrl
                  .replaceAll(RegExp(r'/+$'), '')
                  .toLowerCase();
              final inKnownOrg = orgUrls.any((o) => normalized.startsWith(o));
              if (!inKnownOrg) {
                continue;
              }
              plan[depName] = repoUrl;
            }
          }
        }

        // Dart: scan pubspec.yaml dependencies.
        final pubspecFile = File(path.join(repoDir.path, 'pubspec.yaml'));
        if (pubspecFile.existsSync()) {
          Pubspec? parsed;
          try {
            parsed = Pubspec.parse(pubspecFile.readAsStringSync());
          } catch (_) {
            parsed = null; // skip unparseable pubspec
          }
          if (parsed != null) {
            await scan(parsed.dependencies);
            await scan(parsed.devDependencies);
          }
        }

        // TypeScript: scan package.json for cross-language (npm) deps so a
        // bridge referenced only from the TypeScript side is cloned too.
        _planNpmDepsFromPackageJson(
          repoDir: repoDir,
          knownPackages: knownPackages,
          orgNames: orgNames,
          plan: plan,
        );
      }

      if (plan.isEmpty) {
        return;
      }

      bool addedAny = false;
      for (final entry in plan.entries) {
        final depName = entry.key;
        Directory? destDir = RepoFolderResolver.resolve(
          workspacePath: oceanWorkspacePath,
          repoName: depName,
        );
        if (destDir != null) {
          continue;
        }
        try {
          await addRepositoryHelper(
            targetArg: entry.value,
            ggLog: ggLog,
            gitCloner: gitCloner,
            gitHubPlatform: gitHubPlatform,
            workspacePath: oceanWorkspacePath,
            logIfAlreadyAdded: false,
            selectOrganization: _selectOrganization,
          );
        } catch (_) {
          // Swallow: addRepositoryHelper already logged the failure.
        }
        destDir = RepoFolderResolver.resolve(
          workspacePath: oceanWorkspacePath,
          repoName: depName,
        );
        if (destDir != null) {
          addedAny = true;
        }
      }

      // No progress -> stop (e.g. remaining deps are unreachable).
      if (!addedAny) {
        return;
      }
    }
  }

  // ...........................................................................
  /// Adds the scoped npm dependencies of [repoDir]'s `package.json` to [plan]
  /// when their scope maps to a known organization in [orgNames].
  ///
  /// This is what makes the transitive clone cross-language: a bridge repo
  /// that is only referenced from a TypeScript package (via its npm name,
  /// e.g. `@tssuite/gg-bridge-dart-typescript`) still gets cloned into the
  /// ocean. The bare package name is used as target so that
  /// [addRepositoryHelper] resolves it against the known organization URLs.
  void _planNpmDepsFromPackageJson({
    required Directory repoDir,
    required Set<String> knownPackages,
    required Set<String> orgNames,
    required Map<String, String> plan,
  }) {
    final packageJsonFile = File(path.join(repoDir.path, 'package.json'));
    if (!packageJsonFile.existsSync()) {
      return;
    }

    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(packageJsonFile.readAsStringSync());
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      json = decoded;
    } catch (_) {
      return; // skip unparseable package.json
    }

    void scanSection(String section) {
      final deps = json[section];
      if (deps is! Map<String, dynamic>) {
        return;
      }
      for (final fullName in deps.keys) {
        // Only scoped deps (`@org/name`) can be mapped back to an org.
        if (!fullName.startsWith('@')) {
          continue;
        }
        final slash = fullName.indexOf('/');
        if (slash <= 1 || slash == fullName.length - 1) {
          continue;
        }
        final scope = fullName.substring(1, slash).toLowerCase();
        if (!orgNames.contains(scope)) {
          continue;
        }
        final bareName = fullName.substring(slash + 1);
        if (knownPackages.contains(bareName) || plan.containsKey(bareName)) {
          continue;
        }
        // Bare name: addRepositoryHelper falls back to known org URLs.
        plan[bareName] = bareName;
      }
    }

    scanSection('dependencies');
    scanSection('devDependencies');
  }

  // ...........................................................................
  /// Find a node by package name in the dependency graph.
  Node? findNode({
    required String packageName,
    required Map<String, Node> nodes,
  }) {
    if (nodes.isEmpty) {
      return null;
    }
    Node? node = nodes[packageName];
    if (node != null) {
      return node;
    }
    for (final Node n in nodes.values) {
      // Match by primary name or any cross-language alias (Dart name, npm
      // name, directory name), so a repo can be requested under any of them.
      if (n.name == packageName || n.aliases.contains(packageName)) {
        return n;
      }
      final Node? foundNode = findNode(
        packageName: packageName,
        nodes: n.dependencies,
      );
      if (foundNode != null) {
        return foundNode;
      }
    }
    return null;
  }

  /// Copies all [repoNames] from ocean into the ticket at [ticketPath].
  /// Up to [maxParallel] parallel; status via [reportLog], verbose via
  /// [ggLog].
  Future<void> _copyReposToTicket({
    required String ticketPath,
    required Set<String> repoNames,
    required GgLog ggLog,
    required GgLog reportLog,
    int maxParallel = 4,
  }) async {
    final queue = repoNames.toList();
    var nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        final int index;
        if (nextIndex >= queue.length) {
          return;
        }
        index = nextIndex++;
        final repoName = queue[index];
        await _copyRepoToTicket(
          repoName: repoName,
          ticketPath: ticketPath,
          ggLog: ggLog,
        );
        reportLog(cDetail('  ✓ $repoName'));
      }
    }

    final workers = <Future<void>>[
      for (var i = 0; i < maxParallel && i < queue.length; i++) worker(),
    ];

    await Future.wait(workers);
  }

  /// Copies the repository from the ocean to the [ticketPath] but
  /// does not trigger a ticket-wide relocalization.
  Future<void> _copyRepoToTicket({
    required String repoName,
    required String ticketPath,
    required GgLog ggLog,
  }) async {
    final srcDir = RepoFolderResolver.resolve(
      workspacePath: oceanWorkspacePath,
      repoName: repoName,
    );
    if (srcDir == null) {
      ggLog(cError('Repository $repoName not found in ocean.'));
      return;
    }

    // The ticket copy keeps the location the repo has in the ocean
    // workspace, i.e. `<ticket>/<org>/<repo>`.
    final relativePath = RepoFolderResolver.relativePath(
      workspacePath: oceanWorkspacePath,
      repoDir: srcDir,
    );
    final destDir = Directory(path.join(ticketPath, relativePath));
    if (destDir.existsSync() && destDir.listSync().isNotEmpty) {
      ggLog(darkGray('$repoName already exists in ticket workspace.'));
      return;
    }

    await _prepareOceanRepositoryForCopy(
      repoDir: srcDir,
      repoName: repoName,
      ggLog: ggLog,
    );

    // Copy from ocean into ticket -------------------------------------------
    await copyDirectory(srcDir, destDir);

    final String ticketName = path.basename(ticketPath);

    // Checkout a branch named as the ticket ----------------------------------
    try {
      await gitCloner.checkoutBranch(ticketName, destDir.path);
    } catch (e) {
      ggLog(cError('Failed to checkout branch $ticketName: $e'));
    }

    // Install deps for every package manager the repo uses (Dart and/or TS).
    await installRepoDependencies(
      dir: destDir,
      repoName: repoName,
      ggLog: ggLog,
      processRunner: processRunner,
    );

    ggLog(cDetail('Added repository $repoName to ticket workspace.'));
  }

  /// Prepares the ocean repository state before copying it into a ticket.
  Future<void> _prepareOceanRepositoryForCopy({
    required Directory repoDir,
    required String repoName,
    required GgLog ggLog,
  }) async {
    await _throwIfOceanRepoIsDirty(
      repoDir: repoDir,
      repoName: repoName,
      ggLog: ggLog,
    );
    await _gitFetch(repoDir: repoDir, repoName: repoName, ggLog: ggLog);
    await _gitResetHardToOriginMain(
      repoDir: repoDir,
      repoName: repoName,
      ggLog: ggLog,
    );
    await _gitDeleteAllLocalTags(
      repoDir: repoDir,
      repoName: repoName,
      ggLog: ggLog,
    );
    await _gitFetchTags(repoDir: repoDir, repoName: repoName, ggLog: ggLog);
    await _gitFetchPruneTags(
      repoDir: repoDir,
      repoName: repoName,
      ggLog: ggLog,
    );

    // The runtime progress of a publish (.gg/gg-publish.json) is gitignored,
    // so the reset above never removes it. It records the progress of a
    // publish of ANOTHER branch and must not linger in the ocean —
    // and never reach a ticket copy (copyDirectory skips it too).
    final stalePublishProgress = File(
      path.join(repoDir.path, '.gg', 'gg-publish.json'),
    );
    if (stalePublishProgress.existsSync()) {
      stalePublishProgress.deleteSync();
      ggLog(
        cWarn(
          'Removed stale publish progress '
          '(.gg/gg-publish.json) in $repoName.',
        ),
      );
    }
  }

  /// Throws when the ocean copy of [repoName] carries uncommitted changes.
  ///
  /// The preparation below runs `git reset --hard origin/main`, which would
  /// throw away every modification the user made in the ocean
  /// without a trace. So a dirty repo stops the `add` instead: the user has
  /// to commit, stash or revert the changes first. Untracked files survive
  /// the reset and are therefore not counted as dirty.
  Future<void> _throwIfOceanRepoIsDirty({
    required Directory repoDir,
    required String repoName,
    required GgLog ggLog,
  }) async {
    final result = await processRunner(
      'git',
      <String>['status', '--porcelain', '--untracked-files=no'],
      workingDirectory: repoDir.path,
      runInShell: true,
    );

    // A folder git cannot report on (e.g. no repository at all) has no
    // changes that could be lost — the failure is logged and the following
    // steps report it as well.
    if (result.exitCode != 0) {
      ggLog(
        cError(
          'Failed to execute git status in $repoName in ocean: '
          '${result.stderr}',
        ),
      );
      return;
    }

    final changes = const LineSplitter()
        .convert('${result.stdout}')
        .where((l) => l.trim().isNotEmpty)
        .toList();

    if (changes.isEmpty) {
      return;
    }

    ggLog(
      cError(
        'The repository $repoName in the ocean has uncommitted '
        'changes:',
      ),
    );
    for (final change in changes) {
      ggLog(cError('  $change'));
    }
    ggLog(
      cAction(
        'Commit, stash or revert them before running "gg do add" — '
        'otherwise they would be lost.',
      ),
    );

    throw Exception(cError('Repository $repoName in the ocean is not clean'));
  }

  /// Runs a single git command in [repoDir] and logs success/failure.
  Future<ProcessResult> _runGit({
    required Directory repoDir,
    required List<String> arguments,
    required String successMessage,
    required String failureLabel,
    required GgLog ggLog,
  }) async {
    final result = await processRunner(
      'git',
      arguments,
      workingDirectory: repoDir.path,
      runInShell: true,
    );

    if (result.exitCode != 0) {
      ggLog(cError('Failed to execute $failureLabel: ${result.stderr}'));
    } else {
      ggLog(darkGray(successMessage));
    }
    return result;
  }

  /// Runs `git fetch` in [repoDir].
  Future<void> _gitFetch({
    required Directory repoDir,
    required String repoName,
    required GgLog ggLog,
  }) async {
    await _runGit(
      repoDir: repoDir,
      arguments: <String>['fetch'],
      successMessage: 'Executed git fetch in $repoName in ocean.',
      failureLabel: 'git fetch in $repoName in ocean',
      ggLog: ggLog,
    );
  }

  /// Runs `git reset --hard origin/main` in [repoDir].
  Future<void> _gitResetHardToOriginMain({
    required Directory repoDir,
    required String repoName,
    required GgLog ggLog,
  }) async {
    await _runGit(
      repoDir: repoDir,
      arguments: <String>['reset', '--hard', 'origin/main'],
      successMessage:
          'Executed git reset --hard origin/main in '
          '$repoName in ocean.',
      failureLabel: 'git reset --hard origin/main in $repoName in ocean',
      ggLog: ggLog,
    );
  }

  /// Deletes all local tags in [repoDir] without using a shell pipe.
  /// Lists tags via `git tag -l`, then `git tag -d <tags...>` in one call
  /// (macOS-safe; xargs-pipe variant fails under Process.run).
  Future<void> _gitDeleteAllLocalTags({
    required Directory repoDir,
    required String repoName,
    required GgLog ggLog,
  }) async {
    final list = await _runGit(
      repoDir: repoDir,
      arguments: <String>['tag', '-l'],
      successMessage: 'Listed local tags in $repoName in ocean.',
      failureLabel: 'git tag -l in $repoName in ocean',
      ggLog: ggLog,
    );

    if (list.exitCode != 0) {
      return;
    }

    final tags = (list.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (tags.isEmpty) {
      ggLog(darkGray('No local tags to delete in $repoName in ocean.'));
      return;
    }

    await _runGit(
      repoDir: repoDir,
      arguments: <String>['tag', '-d', ...tags],
      successMessage:
          'Deleted ${tags.length} local tag(s) in $repoName in ocean '
          'workspace.',
      failureLabel: 'git tag -d <tags> in $repoName in ocean',
      ggLog: ggLog,
    );
  }

  /// Runs `git fetch --tags` in [repoDir].
  Future<void> _gitFetchTags({
    required Directory repoDir,
    required String repoName,
    required GgLog ggLog,
  }) async {
    await _runGit(
      repoDir: repoDir,
      arguments: <String>['fetch', '--tags'],
      successMessage: 'Executed git fetch --tags in $repoName in ocean.',
      failureLabel: 'git fetch --tags in $repoName in ocean',
      ggLog: ggLog,
    );
  }

  /// Runs `git fetch --prune --tags` in [repoDir].
  Future<void> _gitFetchPruneTags({
    required Directory repoDir,
    required String repoName,
    required GgLog ggLog,
  }) async {
    await _runGit(
      repoDir: repoDir,
      arguments: <String>['fetch', '--prune', '--tags'],
      successMessage:
          'Executed git fetch --prune --tags in '
          '$repoName in ocean.',
      failureLabel: 'git fetch --prune --tags in $repoName in ocean',
      ggLog: ggLog,
    );
  }

  /// Writes the ticket description next to the repos. It is overwritten on
  /// every `do add`, keeping the repo list current, and it stays local: no
  /// repo carries it, so it is never committed and never pushed.
  ///
  /// Returns the repositories of the ticket in processing order, or an empty
  /// list when the ticket holds none.
  Future<List<Node>> _writeTicketJson({
    required Directory ticketDir,
    required GgLog ggLog,
  }) async {
    final nodes = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );

    if (nodes.isEmpty) {
      ggLog(cWarn('⚠️ No repos in this ticket'));
      return nodes;
    }

    final repoDirs = nodes.map((n) => n.directory).toList();
    writeTicketJson(
      ticketDir,
      buildTicketJson(ticketDir: ticketDir, repoDirs: repoDirs),
    );

    return nodes;
  }

  /// Re-localizes all ticket repos in two passes (sorted order):
  /// 1) unlocalize, 2) localize --git + pub upgrade + commit.
  Future<void> _relocalizeAllReposInTicket({
    required Directory ticketDir,
    required GgLog ggLog,
  }) async {
    final ticketName = path.basename(ticketDir.path);

    final nodes = await _writeTicketJson(ticketDir: ticketDir, ggLog: ggLog);

    if (nodes.isEmpty) {
      return;
    }

    // Iteration 1: Unlocalize all ---------------------------------------------
    for (final node in nodes) {
      final repoDir = node.directory;
      final repoName = path.basename(repoDir.path);
      try {
        // Dart and TypeScript each keep their own backup in .gg today; the
        // shared and root-level names are what older checkouts still carry.
        final backupFiles = [
          for (final name in const <String>[
            'gg_localize_refs_backup_dart.json',
            'gg_localize_refs_backup_ts.json',
            'gg_localize_refs_backup.json',
          ])
            File(path.join(repoDir.path, '.gg', name)),
          File(path.join(repoDir.path, '.gg_localize_refs_backup.json')),
        ];
        if (backupFiles.any((f) => f.existsSync())) {
          await _unlocalizeRefs.get(directory: repoDir, ggLog: ggLog);
        }
      } catch (e) {
        ggLog(cError('Failed to unlocalize refs for $repoName: $e'));
        throw Exception(cError('Failed to relocalize ticket'));
      }
    }

    // Iteration 2: Localize ---------------------------------------------------
    for (final node in nodes) {
      final repoDir = node.directory;
      final repoName = path.basename(repoDir.path);
      try {
        await _backupPublishTo.exec(directory: repoDir, ggLog: ggLog);
        await _localizeRefs.get(directory: repoDir, ggLog: ggLog);
      } catch (e) {
        ggLog(cError('Failed to localize refs for $repoName: $e'));
        throw Exception(cError('Failed to relocalize ticket'));
      }

      // Refresh deps after relocalize (dart pub upgrade and/or pm install).
      await installRepoDependencies(
        dir: repoDir,
        repoName: repoName,
        ggLog: ggLog,
        processRunner: processRunner,
        upgradeDart: true,
      );

      // Commit per repo; skip changelog (gg_changelog needs pubspec.yaml).
      try {
        await _ggDoCommit.exec(
          directory: repoDir,
          ggLog: ggLog,
          message: '#gg: changed references to path',
          force: true,
          updateChangeLog: false,
        );
      } catch (e) {
        ggLog(cError('Failed to commit $repoName: $e'));
      }
    }

    ggLog('✓ Re-localized all repositories in ticket $ticketName.');
  }

  /// Rewrites the VS Code `.code-workspace` file for the given [ticketDir]
  /// with one folder entry per repository in the ticket.
  Future<void> _rewriteCodeWorkspace({
    required Directory ticketDir,
    required GgLog ggLog,
  }) async {
    final nodes = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );

    // The entries are relative to the ticket root, so a repo inside an
    // organization folder is listed as `<org>/<repo>`.
    final folderPaths = <String>{
      for (final node in nodes)
        RepoFolderResolver.relativePath(
          workspacePath: ticketDir.path,
          repoDir: node.directory,
        ),
    };

    writeCodeWorkspaceFile(ticketDir, folderPaths.toList());
  }

  /// Writes all project configuration files that depend on the set of
  /// repositories in a ticket, such as the VS Code workspace and
  /// `.gitattributes`.
  ///
  /// Also removes the obsolete `gg`-generated pre-push hook from every repo of
  /// the ticket. `gg` no longer installs git hooks — pushing to `main` is
  /// blocked by the remote and merges go through pull requests — but a hook
  /// installed by an older `gg do add` survives in checkouts and would keep
  /// running on every push.
  ///
  /// Also drops the lock file entries from every repo's `.gitignore`
  /// (`ensureLockFilesNotIgnored`). A lock file belongs into git, and while it
  /// is ignored, every background `pub get` rewrites a file the checks cannot
  /// see. Running it here migrates a repository the first time it enters a
  /// ticket; the `#gg:` force commit that follows picks the lock file up.
  Future<void> _writeProjectConfigFiles({
    required Directory ticketDir,
    required GgLog ggLog,
  }) async {
    await _rewriteCodeWorkspace(ticketDir: ticketDir, ggLog: ggLog);

    final nodes = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );

    for (final node in nodes) {
      removeLegacyGitHooks(repoDir: node.directory, ggLog: ggLog);
      ensureLockFilesNotIgnored(repoDir: node.directory, ggLog: ggLog);
    }

    await installGitattributes(
      directory: ticketDir,
      ggLog: ggLog,
      sortedProcessingList: _sortedProcessingList,
      processRunner: processRunner,
    );
  }
}
