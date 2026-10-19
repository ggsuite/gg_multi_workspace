// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_create_repo/gg_create_repo.dart' show RunDna;
import 'package:gg_multi_core/gg_multi_core.dart';
import 'package:gg_multi_workspace/src/backend/workspace_dna.dart';
import 'package:gg_multi_workspace/src/commands/do/init/workspace.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('InitWorkspaceCommand', () {
    late Directory tempDir;
    final messages = <String>[];
    final dnaCalls = <List<String>>[];

    void ggLog(String message) {
      messages.add(rmControls(message));
    }

    Future<void> runDna(List<String> args) async {
      dnaCalls.add(args);
    }

    CommandRunner<void> runnerFor(String rootPath, {required RunDna runDna}) =>
        CommandRunner<void>('test', 'InitWorkspaceCommand Test')..addCommand(
          InitWorkspaceCommand(
            ggLog: ggLog,
            rootPath: rootPath,
            runDna: runDna,
          ),
        );

    setUp(() {
      messages.clear();
      dnaCalls.clear();
      tempDir = Directory.systemTemp.createTempSync('init_command_test');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('should create ocean if not exists', () async {
      final runner = runnerFor(tempDir.path, runDna: runDna);
      final wsPath = path.join(tempDir.path, ggMultiOceanFolder);
      expect(Directory(wsPath).existsSync(), isFalse);

      await runner.run(['workspace']);
      expect(messages.any((m) => m.contains('initialized at')), isTrue);
      expect(Directory(wsPath).existsSync(), isTrue);
    });

    /// The one folder all [dnaCalls] aimed at — checked to be no part of
    /// the workspace root.
    String buildFolder() {
      final targets = dnaCalls.map((c) => c[c.indexOf('--target') + 1]).toSet();
      expect(targets, hasLength(1));
      final target = targets.single;
      expect(path.isWithin(tempDir.path, target), isFalse);
      expect(path.equals(tempDir.path, target), isFalse);
      return target;
    }

    test('instantiates dna_gg for the workspace root', () async {
      final runner = runnerFor(tempDir.path, runDna: runDna);
      await runner.run(['workspace']);

      // init, add, build — in this order, all aimed at one temporary
      // folder, never at the workspace root.
      final build = buildFolder();
      // All three steps run quiet: the line below is the whole report a
      // workspace gets — no next steps from init either.
      expect(dnaCalls, [
        ['init', '--target', build, '--language', 'dart', '--quiet'],
        ['add', workspaceDnaLayer, '--target', build, '--workspace', '--quiet'],
        ['build', '--target', build, '--workspace', '--quiet'],
      ]);
      expect(
        messages.last,
        contains('$workspaceDnaLayer instantiated in the workspace'),
      );
    });

    test('leaves no pub scaffold in the root when a step failed', () async {
      Future<void> fakeRunDna(List<String> args) async {
        dnaCalls.add(args);
        final target = args[args.indexOf('--target') + 1];
        if (args.first == 'init') {
          File(path.join(target, 'pubspec.yaml'))
              .writeAsStringSync('name: workspace\n');
          Directory(path.join(target, 'dna')).createSync();
          return;
        }
        throw Exception('pub add failed');
      }

      final runner = runnerFor(tempDir.path, runDna: fakeRunDna);
      await runner.run(['workspace']);

      final entries = tempDir
          .listSync()
          .map((e) => path.basename(e.path))
          .toList();
      expect(entries, [ggMultiOceanFolder]);
      expect(Directory(buildFolder()).existsSync(), isFalse);
    });

    test('keeps the ocean and names the retry when dna fails', () async {
      final runner = runnerFor(
        tempDir.path,
        runDna: (args) async => throw Exception('pub add failed'),
      );
      await runner.run(['workspace']);

      final wsPath = path.join(tempDir.path, ggMultiOceanFolder);
      expect(Directory(wsPath).existsSync(), isTrue);
      expect(
        messages,
        contains(
          'Could not instantiate $workspaceDnaLayer: '
          'Exception: pub add failed',
        ),
      );
      expect(
        messages.last,
        'Run gg do init workspace in the workspace root to try again.',
      );
    });

    test(
      'should not recreate if already exists, but instantiate the dna',
      () async {
        final wsPath = path.join(tempDir.path, ggMultiOceanFolder);
        Directory(wsPath).createSync(recursive: true);
        final runner = runnerFor(tempDir.path, runDna: runDna);

        await runner.run(['workspace']);

        expect(messages[0], contains('ocean already exists at:'));
        expect(messages[0], contains(ggMultiOceanFolder));
        expect(Directory(wsPath).existsSync(), isTrue);

        // The repetition is what brings a workspace without CLAUDE.md to
        // the current guides, so the DNA runs like on a fresh one.
        expect(dnaCalls.map((c) => c.first), ['init', 'add', 'build']);
        buildFolder();
        expect(
          messages.last,
          contains('$workspaceDnaLayer instantiated in the workspace'),
        );
      },
    );

    test('instantiates the dna although the root holds other files', () async {
      // A workspace in use: the ocean is there and so are the tickets
      // beside it. Neither may turn the repetition into an error.
      Directory(path.join(tempDir.path, ggMultiOceanFolder))
          .createSync(recursive: true);
      Directory(path.join(tempDir.path, 'a_ticket')).createSync();
      final runner = runnerFor(tempDir.path, runDna: runDna);

      await runner.run(['workspace']);

      expect(
        messages,
        isNot(
          contains('The directory must be empty to initialize a workspace.'),
        ),
      );
      expect(
        messages.any((m) => m.contains('inside an existing Gg Multi')),
        isFalse,
      );
      expect(dnaCalls.map((c) => c.first), ['init', 'add', 'build']);
    });

    test('should not allow init inside non-empty directory', () async {
      // Arrange:
      final nonEmptyDir = Directory(path.join(tempDir.path, 'not_empty'));
      nonEmptyDir.createSync(recursive: true);
      File(path.join(nonEmptyDir.path, 'some_file.txt'))
          .writeAsStringSync('dummy');
      final runner = runnerFor(nonEmptyDir.path, runDna: runDna);
      // Act
      await runner.run(['workspace']);
      // Assert
      expect(
        messages,
        contains('The directory must be empty to initialize a workspace.'),
      );
      expect(
        Directory(path.join(nonEmptyDir.path, ggMultiOceanFolder)).existsSync(),
        isFalse,
      );
      expect(dnaCalls, isEmpty);
    });

    test(
      'should not allow init inside an existing workspace (nested)',
      () async {
        // Arrange:
        // Create parent workspace
        final parentWs = Directory(path.join(tempDir.path, 'parent'))
          ..createSync();
        final oceanWs = Directory(path.join(parentWs.path, ggMultiOceanFolder))
          ..createSync();
        // Create child directory inside parent
        final childDir = Directory(path.join(oceanWs.path, 'child'))
          ..createSync();
        final runner = runnerFor(childDir.path, runDna: runDna);
        // Directory is empty; ocean exists in ancestor
        await runner.run(['workspace']);
        expect(
          messages,
          contains(
            'Cannot initialize a new workspace '
            'inside an existing Gg Multi workspace.',
          ),
        );
        // No child/ocean folder created
        expect(
          Directory(path.join(childDir.path, ggMultiOceanFolder)).existsSync(),
          isFalse,
        );
        expect(dnaCalls, isEmpty);
      },
    );

    test('prints help when --help is passed', () async {
      final runner = runnerFor(tempDir.path, runDna: runDna);

      expect(() async {
        await runner.run(['workspace', '--help']);
      }, returnsNormally);
    });
  });
}
