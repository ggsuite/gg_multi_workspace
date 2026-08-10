// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;

import 'package:gg_multi_workspace/src/backend/add_repository_helper.dart';
import 'package:gg_multi_core/gg_multi_core.dart';
import 'package:gg_multi_workspace/src/backend/dependency_overrides.dart';

/// Factory for `Directory` instances — overridable in tests.
typedef DirectoryFactory = Directory Function(String path);

/// Deletes repositories from the ticket the command is invoked in.
///
/// Accepts a list of repository names; each is deleted when it is part of
/// the ticket. Several repos are removed dependents-first (reverse
/// dependency order), so a whole chain can go in one call — the
/// chain guard below still refuses to tear a repo out of the *middle* of a
/// chain that stays behind.
///
/// The command must run inside a ticket folder and never touches the master
/// workspace: the ocean holds the only checkout a repo has outside the
/// tickets, so deleting it there is unrecoverable work, not a ticket
/// cleanup. Removing a repo from the ocean is a manual step.
class RemoveRepoCommand extends Command<void> {
  /// Constructor.
  RemoveRepoCommand({
    required this.ggLog,
    String? rootPath,
    DirectoryFactory? directoryFactory,
    SortedProcessingList? sortedProcessingList,
    // coverage:ignore-start
  }) : rootPath = rootPath ?? Directory.current.path,
       directoryFactory = directoryFactory ?? Directory.new,
       // coverage:ignore-end
       _sortedProcessingList =
           sortedProcessingList ?? SortedProcessingList(ggLog: ggLog);

  // ...........................................................................
  @override
  String get name => 'repo';

  // ...........................................................................
  @override
  String get description => 'Delete repos from the current ticket';

  // ...........................................................................
  @override
  Future<void> run() async {
    final targets = argResults!.rest;
    if (targets.isEmpty) {
      throw UsageException('Missing repository name(s).', usage);
    }
    final repoNames = [
      for (final target in targets) extractRepoName(target) ?? 'unknown_repo',
    ];

    final ticketPath = WorkspaceUtils.detectTicketPath(rootPath);
    if (ticketPath == null) {
      throw Exception(
        cError(
          '»gg do rm repo« must be called inside a ticket folder. '
          'It never deletes repos from the master workspace.',
        ),
      );
    }

    _root = ticketPath;
    for (final repoName in await _dependentsFirst(repoNames)) {
      await _removeFromTicket(repoName);
    }
  }

  /// Log sink.
  final GgLog ggLog;

  /// Directory the command was invoked in.
  final String rootPath;

  /// The ticket directory [rootPath] belongs to. Resolved in [run], so the
  /// command also works from any sub-folder.
  late final String _root;

  /// Factory used to materialize Directory handles (tests substitute it).
  final DirectoryFactory directoryFactory;

  /// Resolves the dependency graph of the repos of a ticket.
  final SortedProcessingList _sortedProcessingList;

  // ######################
  // Private
  // ######################

  // ...........................................................................
  /// Orders [repoNames] so dependents are removed before their
  /// dependencies.
  ///
  /// [SortedProcessingList] returns dependencies first, so removing in
  /// *reverse* graph order deletes the outermost dependents first — a whole
  /// chain can then be removed in one call without tripping the chain
  /// guard. Names that resolve to no graph node keep their given order and
  /// go last; their individual removal reports what is wrong with them.
  Future<List<String>> _dependentsFirst(List<String> repoNames) async {
    if (repoNames.length < 2) {
      return repoNames;
    }

    final nodes = await _sortedProcessingList.get(
      directory: directoryFactory(_root),
      ggLog: ggLog,
    );

    int indexOf(String repoName) {
      final repoDir = RepoFolderResolver.resolve(
        workspacePath: _root,
        repoName: repoName,
      );
      for (var i = 0; i < nodes.length; i++) {
        final node = nodes[i];
        final matchesDir =
            repoDir != null && path.equals(node.directory.path, repoDir.path);
        if (matchesDir ||
            node.name == repoName ||
            node.aliases.contains(repoName)) {
          return i;
        }
      }
      return -1;
    }

    final indexed = [
      for (final repoName in repoNames)
        (name: repoName, index: indexOf(repoName)),
    ];

    // Sort is stable, so names with equal indices (esp. the unresolved -1
    // ones, pushed to the end) keep their given order.
    return ([...indexed]..sort((a, b) {
          if (a.index == -1 && b.index == -1) return 0;
          if (a.index == -1) return 1;
          if (b.index == -1) return -1;
          return b.index.compareTo(a.index);
        }))
        .map((e) => e.name)
        .toList();
  }

  // ...........................................................................
  /// Deletes the repo from the ticket the command was invoked in.
  Future<void> _removeFromTicket(String repoName) async {
    final resolved = RepoFolderResolver.resolve(
      workspacePath: _root,
      repoName: repoName,
    );
    final ticketRepoDir =
        resolved ?? directoryFactory(path.join(_root, repoName));
    if (!ticketRepoDir.existsSync()) {
      ggLog(
        cError(
          'Repository $repoName is not part of ticket '
          '${path.basename(_root)}.',
        ),
      );
      return;
    }

    final nodes = await _sortedProcessingList.get(
      directory: directoryFactory(_root),
      ggLog: ggLog,
    );

    _throwIfLinkingOtherRepos(repoName, ticketRepoDir, nodes);

    // Collect the names the repo is referenced by *before* it is gone — the
    // manifest that carries them is deleted with it.
    final removedNames = _packageNamesOf(repoName, ticketRepoDir, nodes);

    ticketRepoDir.deleteSync(recursive: true);
    RepoFolderResolver.removeEmptyOrgFolder(
      workspacePath: _root,
      repoDir: ticketRepoDir,
    );
    ggLog(
      darkGray('✓ Deleted repository ') +
          cCmd(repoName) +
          darkGray(' from ticket ') +
          cCmd(path.basename(_root)) +
          darkGray('.'),
    );

    _updateTicketJson(ticketRepoDir, nodes);
    _removeDependencyOverrides(ticketRepoDir, nodes, removedNames);
  }

  // ...........................................................................
  /// All names the removed repo can appear under in another repo's
  /// `dependency_overrides`: the folder name, the name it was addressed with,
  /// and the package name(s) the dependency graph knows it by.
  Set<String> _packageNamesOf(
    String repoName,
    Directory ticketRepoDir,
    List<Node> nodes,
  ) {
    final names = <String>{repoName, path.basename(ticketRepoDir.path)};
    for (final node in nodes) {
      if (path.equals(node.directory.path, ticketRepoDir.path)) {
        names.add(node.name);
        names.addAll(node.aliases);
      }
    }
    return names;
  }

  // ...........................................................................
  /// Drops the removed repo from the `pubspec_overrides.yaml` and
  /// `pnpm-workspace.yaml` of the repos that stay in the ticket.
  ///
  /// Those overrides point at the sibling checkout (`path: ../<repo>` /
  /// `link:../<repo>`) that just disappeared, so leaving them would break
  /// `dart pub get` / `pnpm install` in every remaining repo.
  void _removeDependencyOverrides(
    Directory removedRepoDir,
    List<Node> nodes,
    Set<String> removedNames,
  ) {
    final remaining = [
      for (final node in nodes)
        if (!path.equals(node.directory.path, removedRepoDir.path))
          node.directory,
    ];

    final changed = removeDependencyOverrides(
      repoDirs: remaining,
      packageNames: removedNames,
    );
    if (changed.isEmpty) {
      return;
    }

    ggLog(
      cDetail(
        '✓ Removed ${path.basename(removedRepoDir.path)} from '
        'the localized overrides of ${changed.length} repo(s).',
      ),
    );
  }

  // ...........................................................................
  /// Throws when the repo sits between two other repos of the ticket, i.e.
  /// when another ticket repo depends on it while it itself depends on a
  /// further ticket repo. Deleting it would break that chain.
  void _throwIfLinkingOtherRepos(
    String repoName,
    Directory ticketRepoDir,
    List<Node> nodes,
  ) {
    final target = nodes.where(
      (node) =>
          path.equals(node.directory.path, ticketRepoDir.path) ||
          node.aliases.contains(repoName),
    );
    if (target.isEmpty) {
      return; // The repo is no package — nothing can depend on it.
    }

    final node = target.first;
    final dependents = node.dependents.keys.toList()..sort();
    final dependencies = node.dependencies.keys.toList()..sort();
    if (dependents.isEmpty || dependencies.isEmpty) {
      return;
    }

    ggLog(
      cError(
        'Repository $repoName connects other repos of ticket '
        '${path.basename(_root)}:',
      ),
    );
    for (final dependent in dependents) {
      ggLog(' - $dependent depends on $repoName');
    }
    for (final dependency in dependencies) {
      ggLog(' - $repoName depends on $dependency');
    }
    ggLog(cError('Please remove ${dependents.join(', ')} first.'));

    throw Exception(
      cError(
        'Cannot remove $repoName: it sits between '
        '${dependents.join(', ')} and ${dependencies.join(', ')}.',
      ),
    );
  }

  // ...........................................................................
  /// Rewrites the ticket's `ticket.json` so the deleted repo no longer shows
  /// up in its repository list.
  ///
  /// Only a ticket that already has a `ticket.json` is updated — one that never
  /// saw a `do add` does not gain one here.
  void _updateTicketJson(Directory removedRepoDir, List<Node> nodes) {
    final ticketDir = directoryFactory(_root);
    if (!File(path.join(ticketDir.path, ticketJsonFileName)).existsSync()) {
      return;
    }

    final remaining = [
      for (final node in nodes)
        if (!path.equals(node.directory.path, removedRepoDir.path))
          node.directory,
    ];

    writeTicketJson(
      ticketDir,
      buildTicketJson(ticketDir: ticketDir, repoDirs: remaining),
    );
    ggLog(
      cDetail(
        '✓ Removed ${path.basename(removedRepoDir.path)} from '
        '$ticketJsonFileName.',
      ),
    );
  }
}
