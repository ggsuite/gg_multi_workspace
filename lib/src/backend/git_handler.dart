// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_git/gg_git.dart';

import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_process/gg_process.dart';

/// Typedef for a process runner function.
/// A class responsible for cloning git repositories and performing Git/utility operations.
class GitHandler {
  /// The function used to run system processes.
  final ProcessRunner processRunner;

  /// Constructor accepts an optional [processRunner]
  /// to enable testing by injection.
  GitHandler({ProcessRunner? processRunner})
    : processRunner = processRunner ?? ggRunProcess;

  /// Clones the repository from [repoUrl] into [targetDirectory].
  /// Throws an exception if cloning fails.
  Future<void> cloneRepo(String repoUrl, String targetDirectory) async {
    // Ensure the parent directory exists. A clone that fails must not leave
    // the folders behind that were created for it, so the outermost folder
    // created here is remembered and removed again below.
    final directory = Directory(targetDirectory);
    final createdRoot = _createParentDirectories(directory);

    // Run the git clone command using the injected process runner.
    final result = await processRunner('git', <String>[
      'clone',
      repoUrl,
      targetDirectory,
    ]);
    if (result.exitCode != 0) {
      _removeLeftovers(target: directory, createdRoot: createdRoot);

      throw Exception(
        cError('Failed to clone repo from $repoUrl: ${result.stderr}'),
      );
    }
  }

  /// Creates the parent folders of [directory] and returns the outermost one
  /// that had to be created, or null when they all existed already.
  Directory? _createParentDirectories(Directory directory) {
    final parent = directory.parent;
    if (parent.existsSync()) {
      return null;
    }

    // Walk up to the first existing ancestor: everything below it is new and
    // belongs to this clone alone.
    var outermost = parent;
    while (!outermost.parent.existsSync() &&
        outermost.parent.path != outermost.path) {
      outermost = outermost.parent;
    }

    parent.createSync(recursive: true);
    return outermost;
  }

  /// Removes what a failed clone left behind: the target folder when git
  /// created but did not fill it, and the folders [_createParentDirectories]
  /// made for it. Only empty folders are deleted, so a folder that meanwhile
  /// holds another repository survives.
  void _removeLeftovers({
    required Directory target,
    required Directory? createdRoot,
  }) {
    _deleteIfEmpty(target);
    if (createdRoot != null) {
      _deleteIfEmpty(createdRoot);
    }
  }

  /// Deletes [directory] when it is empty, after doing the same for its
  /// subfolders — so a tree of empty folders vanishes bottom up.
  void _deleteIfEmpty(Directory directory) {
    if (!directory.existsSync()) {
      return;
    }
    for (final entry in directory.listSync()) {
      if (entry is Directory) {
        _deleteIfEmpty(entry);
      }
    }
    if (directory.listSync().isEmpty) {
      directory.deleteSync();
    }
  }

  /// Returns true when [repoUrl] points at a git repository the caller can
  /// reach. Used to find out which organizations own a repository of a given
  /// name without cloning any of them.
  ///
  /// `ls-remote` is asked without `--exit-code`, so a repository that exists
  /// but is still empty counts as present too.
  Future<bool> remoteExists(String repoUrl) async {
    try {
      final result = await processRunner('git', <String>['ls-remote', repoUrl]);
      return result.exitCode == 0;
    } catch (_) {
      // A missing git binary must not look like a missing repository.
      return false;
    }
  }

  /// Checks out a new branch [branchName] in the repository at [repoPath].
  /// Throws an exception if the checkout fails.
  Future<void> checkoutBranch(String branchName, String repoPath) async {
    final result = await processRunner('git', <String>[
      '-C',
      repoPath,
      'checkout',
      '-b',
      branchName,
    ]);
    if (result.exitCode != 0) {
      throw Exception(
        cError(
          'Failed to checkout branch $branchName in $repoPath: '
          '${result.stderr}',
        ),
      );
    }
  }
}
