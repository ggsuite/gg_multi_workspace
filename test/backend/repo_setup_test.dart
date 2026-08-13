// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_git/gg_git.dart';

import 'dart:convert';
import 'dart:io';

import 'package:gg_multi_workspace/src/backend/repo_setup.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  final messages = <String>[];

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('repo_setup_test');
    messages.clear();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Directory repoWith({bool pubspec = false, bool packageJson = false}) {
    final d = Directory(path.join(tmp.path, 'r'))..createSync(recursive: true);
    if (pubspec) {
      File(path.join(d.path, 'pubspec.yaml')).writeAsStringSync('name: x\n');
    }
    if (packageJson) {
      File(path.join(d.path, 'package.json')).writeAsStringSync('{}');
    }
    return d;
  }

  group('installRepoDependencies', () {
    final calls = <List<String>>[];

    ProcessRunner runner({int exitCode = 0}) =>
        (exe, args, {workingDirectory, runInShell = false, environment}) async {
          calls.add(<String>[exe, ...args]);
          return ProcessResult(0, exitCode, '', 'boom');
        };

    setUp(calls.clear);

    test('runs dart pub get and logs success', () async {
      await installRepoDependencies(
        dir: repoWith(pubspec: true),
        repoName: 'r',
        ggLog: messages.add,
        processRunner: runner(),
      );
      expect(calls, [
        ['dart', 'pub', 'get'],
      ]);
      expect(
        messages.any((m) => m.contains('Executed dart pub get in r.')),
        isTrue,
      );
    });

    test('uses dart pub upgrade when upgradeDart is true', () async {
      await installRepoDependencies(
        dir: repoWith(pubspec: true),
        repoName: 'r',
        ggLog: messages.add,
        processRunner: runner(),
        upgradeDart: true,
      );
      expect(calls, [
        ['dart', 'pub', 'upgrade'],
      ]);
    });

    test('runs the TypeScript package manager install', () async {
      await installRepoDependencies(
        dir: repoWith(packageJson: true),
        repoName: 'r',
        ggLog: messages.add,
        processRunner: runner(),
      );
      expect(calls.single.last, 'install');
      expect(messages.any((m) => m.contains('install in r.')), isTrue);
    });

    test('logs a failure on a non-zero exit code', () async {
      await installRepoDependencies(
        dir: repoWith(pubspec: true),
        repoName: 'r',
        ggLog: messages.add,
        processRunner: runner(exitCode: 1),
      );
      expect(
        messages.any(
          (m) => m.contains('Failed to execute dart pub get in r: boom'),
        ),
        isTrue,
      );
    });

    test('does nothing when neither manifest exists', () async {
      await installRepoDependencies(
        dir: repoWith(),
        repoName: 'r',
        ggLog: messages.add,
        processRunner: runner(),
      );
      expect(calls, isEmpty);
      expect(messages, isEmpty);
    });
  });

  group('writeCodeWorkspaceFile', () {
    test('writes a deduplicated folder list with trailing newline', () {
      final ticketDir = Directory(path.join(tmp.path, 'my_ticket'))
        ..createSync();
      writeCodeWorkspaceFile(ticketDir, ['a', 'b', 'a']);
      final file = File(path.join(ticketDir.path, 'my_ticket.code-workspace'));
      expect(
        file.readAsStringSync(),
        '{"folders":[{"path":"a"},{"path":"b"}],'
        '"settings":{"dart.runPubGetOnPubspecChanges":"never"}}\n',
      );
    });

    test('turns the automatic pub get of the Dart extension off', () {
      // Its FileSystemWatcher fires on gg's own CLI writes too and rewrites
      // the lock file a second later, right under the running command.
      final ticketDir = Directory(path.join(tmp.path, 'settings_ticket'))
        ..createSync();
      writeCodeWorkspaceFile(ticketDir, ['a']);
      final written = jsonDecode(
        File(path.join(ticketDir.path, 'settings_ticket.code-workspace'))
            .readAsStringSync(),
      ) as Map<String, dynamic>;

      expect(written['settings'], codeWorkspaceSettings);
      expect(
        (written['settings'] as Map<String, dynamic>).containsKey(
          'dart.runPubGetOnPubspecChanges',
        ),
        isTrue,
      );
      expect(
        (written['settings']
            as Map<String, dynamic>)['dart.runPubGetOnPubspecChanges'],
        'never',
      );
    });

    test('falls back to the ticket folder when there is no repo', () {
      // An empty folder list would open a window showing nothing at all.
      final ticketDir = Directory(path.join(tmp.path, 'empty_ticket'))
        ..createSync();
      writeCodeWorkspaceFile(ticketDir, const <String>[]);
      expect(
        File(path.join(ticketDir.path, 'empty_ticket.code-workspace'))
            .readAsStringSync(),
        '{"folders":[{"path":"."}],'
        '"settings":{"dart.runPubGetOnPubspecChanges":"never"}}\n',
      );
    });

    test('writes org folder entries with forward slashes', () {
      // VS Code understands forward slashes on every platform, a Windows
      // separator would end up escaped in the JSON.
      final ticketDir = Directory(path.join(tmp.path, 'org_ticket'))
        ..createSync();
      writeCodeWorkspaceFile(ticketDir, [path.join('ggsuite', 'gg_foo')]);
      final file = File(path.join(ticketDir.path, 'org_ticket.code-workspace'));
      expect(
        file.readAsStringSync(),
        '{"folders":[{"path":"ggsuite/gg_foo"}],'
        '"settings":{"dart.runPubGetOnPubspecChanges":"never"}}\n',
      );
    });
  });
}
