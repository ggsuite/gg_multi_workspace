// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_multi_core/gg_multi_core.dart';
import 'package:gg_one/gg_one.dart' show GgPrompts;
import 'package:gg_multi_workspace/src/commands/do/init/workspace.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

/// Prompts that record the question and always pick the last option.
class _RecordingPrompts extends GgPrompts {
  String? prompt;
  List<String>? options;

  @override
  Future<int> select({
    required String prompt,
    required List<String> options,
    int initialIndex = 0,
  }) async {
    this.prompt = prompt;
    this.options = options;
    return options.length - 1;
  }

  @override
  Future<String> input({
    required String prompt,
    String? defaultValue,
    String? initialText,
    bool asMessageEditor = false,
  }) async => defaultValue ?? '';
}

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

    test('instantiates dna_gg in the workspace root', () async {
      final runner = runnerFor(tempDir.path, runDna: runDna);
      await runner.run(['workspace']);

      // init, add, build — in this order, all aimed at the workspace root.
      final root = tempDir.path.replaceAll(r'\', '/');
      expect(dnaCalls, [
        ['init', '--target', root, '--language', 'dart'],
        ['add', workspaceDnaLayer, '--target', root],
        ['build', '--target', root],
      ]);
      expect(
        messages.last,
        contains('$workspaceDnaLayer instantiated in the workspace'),
      );

      // The DNA build insists on a LICENSE; the workspace gets its own.
      final license = File(path.join(tempDir.path, 'LICENSE'));
      expect(license.readAsStringSync(), workspaceLicense);
    });

    test('keeps the ocean and names the manual steps when dna fails', () async {
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
        contains(
          'gg dna init --language dart, gg dna add $workspaceDnaLayer, '
          'gg dna build',
        ),
      );
    });

    test('helixDnaRunner runs the helix commands under gg dna', () async {
      // `--help` is the one call that touches neither the package managers
      // nor the file system.
      await expectLater(helixDnaRunner(ggLog)(['--help']), completes);
    });

    test('helixSelectPrompt asks through the gg prompts', () async {
      final prompts = _RecordingPrompts();
      GgPrompts.current = prompts;
      addTearDown(() => GgPrompts.current = null);

      final index = await helixSelectPrompt(
        prompt: 'Which language?',
        options: ['Dart', 'TypeScript'],
      );
      expect(index, 1);
      expect(prompts.prompt, 'Which language?');
      expect(prompts.options, ['Dart', 'TypeScript']);
    });

    test(
      'should not recreate if already exists, and log accordingly',
      () async {
        final wsPath = path.join(tempDir.path, ggMultiOceanFolder);
        Directory(wsPath).createSync(recursive: true);
        final runner = runnerFor(tempDir.path, runDna: runDna);

        await runner.run(['workspace']);

        expect(messages[0], contains('ocean already exists at:'));
        expect(messages[0], contains(ggMultiOceanFolder));
        expect(Directory(wsPath).existsSync(), isTrue);
        expect(dnaCalls, isEmpty);
      },
    );

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
