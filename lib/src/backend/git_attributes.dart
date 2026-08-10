// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_process/gg_process.dart';
import 'package:path/path.dart' as path;

import 'package:gg_multi_core/gg_multi_core.dart';

/// The lines `gg` and the ticket workflow require in *every* repository's
/// `.gitattributes` file, no matter which language it is written in.
///
/// - `* text=auto eol=lf` enables automatic EOL conversion to LF (required
///   by `gg`).
/// - The `merge=ours` rules ensure that generated/state files are not
///   merged textually but kept from the current branch. The rule is
///   `.gg/gg.json` — the state file is named `gg.json`, not `.gg.json`.
/// - `CHANGELOG.md merge=union` keeps the entries of *both* sides instead
///   of conflicting when main and the feature branch both added a line.
///   `union` is a built-in git driver and needs no `git config`.
const String gitattributesCommonLines =
    '* text=auto eol=lf\n'
    '.gg/gg.json merge=ours\n'
    'CHANGELOG.md merge=union';

/// The lock files that are kept from the current branch instead of being
/// merged textually, mapped to the manifest that makes them relevant.
///
/// A lock file rule is only written when the repository actually is of that
/// language — a pure TypeScript repo must not be told about `pubspec.lock`,
/// and a Dart repo not about `pnpm-lock.yaml`.
const Map<String, List<String>> gitattributesLockFilesByManifest =
    <String, List<String>>{
      'pubspec.yaml': <String>['pubspec.lock'],
      'package.json': <String>[
        'package-lock.json',
        'pnpm-lock.yaml',
        'yarn.lock',
      ],
    };

/// The lines `.gitattributes` of the repository at [repoPath] must contain.
///
/// That is [gitattributesCommonLines] plus a `merge=ours` rule for each lock
/// file of the languages the repository uses — detected by the manifests
/// (`pubspec.yaml`, `package.json`) lying in its root.
List<String> gitattributesRequiredLinesFor(String repoPath) {
  final lines = const LineSplitter()
      .convert(gitattributesCommonLines)
      .where((l) => l.isNotEmpty)
      .toList();

  for (final entry in gitattributesLockFilesByManifest.entries) {
    if (!File(path.join(repoPath, entry.key)).existsSync()) {
      continue;
    }

    // A repo uses one of the lock files of its language. Only the existing
    // ones get a rule; when none exists yet, the canonical one is written so
    // the rule is in place once the lock file appears.
    final existing = entry.value
        .where((l) => File(path.join(repoPath, l)).existsSync())
        .toList();

    for (final lockFile
        in existing.isEmpty ? <String>[entry.value.first] : existing) {
      lines.add('$lockFile merge=ours');
    }
  }

  return lines;
}

/// Ensures a `.gitattributes` file containing all lines
/// [gitattributesRequiredLinesFor] returns for the repository exists in every
/// repository of the ticket [directory] lies in, and that the `merge=ours`
/// driver is configured locally.
///
/// `gg` refuses to operate (e.g. `gg do commit`) when automatic EOL
/// conversion is not configured via `.gitattributes`. In addition, the
/// ticket workflow relies on `merge=ours` rules for state files and on
/// `merge=union` for the changelog so that merging main into a feature
/// branch does not produce textual conflicts. The referenced `ours` driver
/// only works once `git config merge.ours.driver true` has been set in each
/// repository; `union` is built into git.
///
/// Behaviour per repository:
/// - If `.gitattributes` does not exist, it is created containing all
///   required lines.
/// - If `.gitattributes` exists, every required line that is missing is
///   appended individually.
/// - If all required lines are already present, the file is left
///   untouched.
/// - If a `.git` directory exists, `git config merge.ours.driver true` is
///   executed with the repository as the working directory so the
///   `merge=ours` rules can be honored by git.
///
/// This used to be the `do install-gitattributes` command. It is not exposed
/// on the CLI any more — `do add` is the only caller and runs it for you.
Future<void> installGitattributes({
  required Directory directory,
  required GgLog ggLog,
  SortedProcessingList? sortedProcessingList,
  ProcessRunner? processRunner,
}) async {
  final list = sortedProcessingList ?? SortedProcessingList(ggLog: ggLog);
  final runner = processRunner ?? ggRunProcess;

  // Detect ticket folder -----------------------------------------------------
  final String? ticketPath = WorkspaceUtils.detectTicketPath(
    path.absolute(directory.path),
  );
  if (ticketPath == null) {
    ggLog(cAction('Please run this command inside a ticket folder.'));
    throw Exception(cDetail('Not inside a ticket folder'));
  }

  final ticketDir = Directory(ticketPath);
  final ticketName = path.basename(ticketDir.path);

  // Collect all repositories in the ticket ----------------------------------
  final nodes = await list.get(directory: ticketDir, ggLog: ggLog);

  if (nodes.isEmpty) {
    ggLog(cWarn('⚠️ No repos in this ticket'));
    return;
  }

  // Ensure .gitattributes and merge.ours driver in each repository ----------
  for (final node in nodes) {
    final repoDir = node.directory;
    final repoName = path.basename(repoDir.path);

    final requiredLines = gitattributesRequiredLinesFor(repoDir.path);

    final attributesFile = File(path.join(repoDir.path, '.gitattributes'));

    if (!attributesFile.existsSync()) {
      await attributesFile.writeAsString('${requiredLines.join('\n')}\n');
      ggLog('Created .gitattributes in $repoName.');
    } else {
      final existing = await attributesFile.readAsString();
      final existingLines = const LineSplitter()
          .convert(existing)
          .map((l) => l.trim())
          .toSet();

      final missingLines = requiredLines
          .where((l) => !existingLines.contains(l))
          .toList();

      if (missingLines.isNotEmpty) {
        final needsLeadingNewline =
            existing.isNotEmpty && !existing.endsWith('\n');
        final prefix = needsLeadingNewline ? '\n' : '';
        await attributesFile.writeAsString(
          '$prefix${missingLines.join('\n')}\n',
          mode: FileMode.append,
        );
        ggLog('Updated .gitattributes in $repoName.');
      }
    }

    // Configure the `ours` merge driver locally so the `merge=ours`
    // rules in .gitattributes resolve to a real git driver.
    final gitDir = Directory(path.join(repoDir.path, '.git'));
    if (!gitDir.existsSync()) {
      ggLog(
        cWarn(
          'Skipping merge.ours driver config for $repoName because no '
          '.git directory was found.',
        ),
      );
      continue;
    }

    final result = await runner(
      'git',
      <String>['config', 'merge.ours.driver', 'true'],
      workingDirectory: repoDir.path,
      runInShell: ggPlatform.isWindows,
    );

    if (result.exitCode != 0) {
      ggLog(
        cError(
          'Failed to configure merge.ours driver in $repoName: '
          '${result.stderr}',
        ),
      );
      throw Exception(
        cError('git config merge.ours.driver true failed in $repoName'),
      );
    }

    ggLog('Configured merge.ours driver in $repoName.');
  }

  ggLog(
    '✓ Ensured .gitattributes for all repositories in ticket '
    '$ticketName.',
  );
}
