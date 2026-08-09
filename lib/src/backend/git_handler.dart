// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_git/gg_git.dart';
import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';

/// Typedef for a process runner function.
/// A class responsible for cloning git repositories and performing Git/utility operations.
class GitHandler {
  /// The function used to run system processes.
  final ProcessRunner processRunner;

  /// Constructor accepts an optional [processRunner]
  /// to enable testing by injection.
  GitHandler({ProcessRunner? processRunner})
    : processRunner = processRunner ?? Process.run;

  /// Clones the repository from [repoUrl] into [targetDirectory].
  /// Throws an exception if cloning fails.
  Future<void> cloneRepo(String repoUrl, String targetDirectory) async {
    // Ensure the parent directory exists.
    final directory = Directory(targetDirectory);
    if (!directory.parent.existsSync()) {
      await directory.parent.create(recursive: true);
    }
    // Run the git clone command using the injected process runner.
    final result = await processRunner('git', <String>[
      'clone',
      repoUrl,
      targetDirectory,
    ]);
    if (result.exitCode != 0) {
      throw Exception(
        cError('Failed to clone repo from $repoUrl: ${result.stderr}'),
      );
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
