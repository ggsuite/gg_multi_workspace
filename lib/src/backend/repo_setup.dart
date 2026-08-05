// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_one/gg_one.dart' as gg;
import 'package:path/path.dart' as path;

/// Runs a process; the named-argument shape used across gg_multi commands.
typedef ProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      bool runInShell,
    });

/// Installs dependencies for every package manager the repo in [dir] uses.
///
/// A cross-language bridge repo carrying both a `pubspec.yaml` and a
/// `package.json` gets both its Dart and its TypeScript dependencies
/// installed. When [upgradeDart] is true, `dart pub upgrade` is used instead
/// of `dart pub get` (used after re-localizing references).
Future<void> installRepoDependencies({
  required Directory dir,
  required String repoName,
  required GgLog ggLog,
  required ProcessRunner processRunner,
  bool upgradeDart = false,
}) async {
  final commands = <List<String>>[];

  if (File(path.join(dir.path, 'pubspec.yaml')).existsSync()) {
    commands.add(<String>['dart', 'pub', upgradeDart ? 'upgrade' : 'get']);
  }
  if (File(path.join(dir.path, 'package.json')).existsSync()) {
    final pm = gg.detectTypeScriptPackageManager(dir).executable;
    commands.add(<String>[pm, 'install']);
  }

  for (final command in commands) {
    final result = await processRunner(
      command.first,
      command.sublist(1),
      workingDirectory: dir.path,
      runInShell: true,
    );
    final cmd = command.join(' ');
    if (result.exitCode == 0) {
      ggLog(darkGray('Executed $cmd in $repoName.'));
    } else {
      ggLog(cError('Failed to execute $cmd in $repoName: ${result.stderr}'));
    }
  }
}

/// The settings every ticket workspace carries.
///
/// The Dart VS Code extension watches `**/pubspec{,_overrides}.yaml` with a
/// `FileSystemWatcher`, which fires on *any* write — including the ones gg
/// makes from the CLI while localizing references — and then runs `pub get`
/// about a second later. That rewrites the lock file behind the back of
/// whatever gg is doing at that moment, so the tree gg just committed is
/// dirty again. `never` is the extension's own off switch for it
/// (`always` is the default, `prompt` would put a dialog on every repo of
/// every `do add`). Nothing is lost: gg runs `pub get`/`pub upgrade` itself
/// wherever the resolution really changed, and `Dart: Get Packages` is still
/// there for a manual edit.
///
/// The key is resource-scoped, so it applies to every folder of the
/// workspace — but a folder's own `.vscode/settings.json` still wins over it.
const Map<String, Object?> codeWorkspaceSettings = <String, Object?>{
  'dart.runPubGetOnPubspecChanges': 'never',
};

/// Writes the VS Code `.code-workspace` file for [ticketDir] with one folder
/// entry per repository in [repoPaths] (deduplicated, insertion order kept).
///
/// Each entry is the path of the repository relative to [ticketDir], i.e.
/// `<org>/<repo>`. It is always written with forward slashes — VS Code
/// understands those on every platform, a Windows separator would end up
/// escaped in the JSON.
///
/// A ticket without repositories — a freshly created one — gets the ticket
/// folder itself as its single entry. An empty folder list would open a
/// window showing nothing at all, and VS Code offers no way to add the first
/// folder from there.
///
/// The file also carries [codeWorkspaceSettings]. It is rewritten on every
/// `do create ticket` and `do add`, so the settings reach an existing ticket
/// as well.
void writeCodeWorkspaceFile(Directory ticketDir, List<String> repoPaths) {
  final folders = (repoPaths.isEmpty ? const <String>['.'] : repoPaths)
      .toSet()
      .map<Map<String, String>>(
        (repoPath) => <String, String>{
          'path': path.posix.joinAll(path.split(repoPath)),
        },
      )
      .toList();
  final ticketName = path.basename(ticketDir.path);
  final file = File(path.join(ticketDir.path, '$ticketName.code-workspace'));
  final content = jsonEncode(<String, Object?>{
    'folders': folders,
    'settings': codeWorkspaceSettings,
  });
  file.writeAsStringSync('$content\n');
}
