// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_localize_refs/gg_localize_refs.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// The file gg_localize_refs writes the local path overrides to.
const String pubspecOverridesFileName = 'pubspec_overrides.yaml';

/// Removes [packageNames] from the localized overrides of every repo in
/// [repoDirs] — the `dependency_overrides` of `pubspec_overrides.yaml`
/// (Dart) and the `overrides` of `pnpm-workspace.yaml` (pnpm-managed
/// TypeScript) — and returns the directories whose files were changed.
///
/// gg_localize_refs points those overrides at the sibling checkouts of the
/// ticket (`path: ../<repo>` / `link:../<repo>`). When a repo leaves the
/// ticket, its entry becomes a dangling path and every `pub get` /
/// `pnpm install` of the remaining repos fails — so the entry goes with it.
/// A file that holds nothing but the removed entries is deleted instead of
/// left behind as an empty override.
///
/// Repos without the files, without an overrides section, or without any of
/// [packageNames] are left untouched. An unparsable file is skipped as
/// well: it is the user's, and guessing at it could destroy it.
List<Directory> removeDependencyOverrides({
  required Iterable<Directory> repoDirs,
  required Set<String> packageNames,
}) {
  final changed = <Directory>[];
  if (packageNames.isEmpty) return changed;

  for (final repoDir in repoDirs) {
    var repoChanged = false;

    final file = File(path.join(repoDir.path, pubspecOverridesFileName));
    if (file.existsSync()) {
      repoChanged = _removeDartOverrides(file, packageNames);
    }

    repoChanged = _removePnpmOverrides(repoDir, packageNames) || repoChanged;

    if (repoChanged) {
      changed.add(repoDir);
    }
  }

  return changed;
}

/// Removes [packageNames] from the `dependency_overrides` of [file].
/// Returns whether the file was changed (or deleted).
bool _removeDartOverrides(File file, Set<String> packageNames) {
  final content = file.readAsStringSync();
  final Object? parsed;
  try {
    parsed = loadYaml(content);
  } on YamlException {
    return false;
  }
  if (parsed is! YamlMap) return false;

  final overrides = parsed['dependency_overrides'];
  if (overrides is! YamlMap) return false;

  final toRemove = packageNames.where(overrides.containsKey).toList();
  if (toRemove.isEmpty) return false;

  if (toRemove.length == overrides.length) {
    // Nothing would be left to override — an empty `dependency_overrides`
    // is invalid for pub, so the generated file goes away entirely.
    file.deleteSync();
    return true;
  }

  final editor = YamlEditor(content);
  for (final name in toRemove) {
    editor.remove(<Object>['dependency_overrides', name]);
  }
  file.writeAsStringSync(editor.toString());
  return true;
}

/// Removes the `overrides` entries of [packageNames] from the
/// `pnpm-workspace.yaml` of [repoDir]. Returns whether the file was changed
/// (or deleted).
///
/// The TypeScript counterpart of the `pubspec_overrides.yaml` cleanup:
/// gg_localize_refs redirects pnpm-managed dependencies through
/// `overrides: {<name>: link:../<repo>}`, and a repo that leaves the ticket
/// turns its entry into a dangling symlink target every `pnpm install` of
/// the remaining repos fails on. Delegates to
/// [PnpmWorkspaceIo.removeOwnedOverrides], so foreign settings and hand
/// written overrides survive and the file is deleted only when
/// gg_localize_refs created it. An unparsable file is the user's and is
/// left untouched.
bool _removePnpmOverrides(Directory repoDir, Set<String> packageNames) {
  const io = PnpmWorkspaceIo();
  if (!io.file(repoDir).existsSync()) return false;

  final PubspecOverridesEdit edit;
  try {
    edit = io.removeOwnedOverrides(
      projectDir: repoDir,
      dependencyNames: packageNames,
    );
  } on Exception {
    return false;
  }

  if (edit.isUnchanged) return false;

  if (edit.deleteFile) {
    io.file(repoDir).deleteSync();
    return true;
  }

  io.file(repoDir).writeAsStringSync(edit.content!);
  return true;
}
