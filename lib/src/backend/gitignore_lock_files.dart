// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;

import 'package:gg_multi_workspace/src/backend/git_attributes.dart'
    show gitattributesLockFilesByManifest;

/// The lock file names that must be committable in the repository at
/// [repoPath] — one entry per language the repository actually uses.
///
/// The names come from [gitattributesLockFilesByManifest], the same catalog
/// that decides which `merge=ours` rules a repository gets: a pure TypeScript
/// repo must not be told about `pubspec.lock`, and a Dart repo not about
/// `pnpm-lock.yaml`.
///
/// Unlike `gitattributesRequiredLinesFor`, *all* lock files of a matching
/// language are returned, not only the ones that exist on disk. A lock file
/// that has not been generated yet must not be ignored either — otherwise the
/// entry would silently start hiding it the moment it appears.
List<String> lockFileNamesFor(String repoPath) {
  final names = <String>[];

  for (final entry in gitattributesLockFilesByManifest.entries) {
    if (!File(path.join(repoPath, entry.key)).existsSync()) {
      continue;
    }
    names.addAll(entry.value);
  }

  return names;
}

/// Ensures `.gitignore` of [repoDir] does **not** exclude any of the lock
/// files [lockFileNamesFor] reports for it. Returns `true` when the file was
/// changed.
///
/// A lock file records the exact resolution a repository was built and tested
/// against, so it belongs into git. While it is ignored instead, every
/// `pub get` — including the one the Dart VS Code extension fires whenever a
/// manifest is written — silently rewrites a file nobody can see, and the
/// checks that compare the working tree against the last commit cannot tell a
/// deliberate dependency change from that background noise.
///
/// Both the bare (`pubspec.lock`) and the anchored (`/pubspec.lock`) form are
/// removed, together with a comment block sitting directly above the entry:
/// such a block explains only the entry it introduces, and leaving it behind
/// would keep a rule in every `.gitignore` that no longer exists.
///
/// The entry has to go **before** the lock file is first committed: gitignored
/// *and* checked in is the one combination that makes `dart pub publish` fail
/// with "checked-in files are ignored by a .gitignore" (exit 65).
bool ensureLockFilesNotIgnored({
  required Directory repoDir,
  required GgLog ggLog,
}) {
  final lockFiles = lockFileNamesFor(repoDir.path);
  if (lockFiles.isEmpty) {
    return false;
  }

  final entries = <String>{
    for (final lockFile in lockFiles) ...<String>[lockFile, '/$lockFile'],
  };

  final changed = _editGitignore(repoDir, (List<String> lines) {
    final removals = <int>{};

    for (var i = 0; i < lines.length; i++) {
      if (!entries.contains(lines[i].trim())) {
        continue;
      }
      removals.add(i);
      removals.addAll(_commentBlockAbove(lines, i));
    }

    if (removals.isEmpty) {
      return;
    }

    for (final index in removals.toList()..sort((a, b) => b.compareTo(a))) {
      lines.removeAt(index);
    }
  });

  if (changed) {
    ggLog(
      'Removed the lock file entries from .gitignore of '
      '${path.basename(repoDir.path)}.',
    );
  }

  return changed;
}

/// The indices of the comment lines directly above [index] in [lines].
///
/// Walking stops at the first line that is not a comment — a blank line or
/// another entry included. That is what keeps a block introducing several
/// entries alive when only one of them is removed: reaching the kept entry
/// ends the walk before its comment is seen.
Set<int> _commentBlockAbove(List<String> lines, int index) {
  final block = <int>{};

  for (var i = index - 1; i >= 0; i--) {
    if (!lines[i].trim().startsWith('#')) {
      break;
    }
    block.add(i);
  }

  return block;
}

/// Reads `.gitignore` of [repoDir] as lines, hands them to [edit] and writes
/// the result back. Returns `true` when the file was changed.
///
/// A missing file is treated as empty and is never created — a repository
/// without a `.gitignore` ignores nothing and needs no rewrite. Nothing is
/// written when [edit] leaves the lines as they are, so a repository that is
/// already correct keeps its file mtime and stays out of `git status`.
///
/// This mirrors `ManifestCommandSupport._editGitignore` in `gg_localize_refs`,
/// which does the same for `pubspec_overrides.yaml`. It is duplicated rather
/// than shared because that helper is private to its package.
bool _editGitignore(Directory repoDir, void Function(List<String>) edit) {
  final gitignore = File(path.join(repoDir.path, '.gitignore'));
  final existed = gitignore.existsSync();
  final raw = existed ? gitignore.readAsStringSync() : '';
  final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final content = normalized.endsWith('\n')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
  final lines = content.isEmpty ? <String>[] : content.split('\n');

  edit(lines);

  final updated = lines.isEmpty ? '' : '${lines.join('\n')}\n';
  if (updated == raw || (!existed && updated.isEmpty)) {
    return false;
  }

  gitignore.writeAsStringSync(updated);
  return true;
}
