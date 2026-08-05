// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_multi_core/gg_multi_core.dart';
import 'package:gg_multi_workspace/src/commands/do/init/workspace.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('InitWorkspaceCommand', () {
    late Directory tempDir;
    final messages = <String>[];

    void ggLog(String message) {
      messages.add(rmControls(message));
    }

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync('init_command_test');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('should create ocean if not exists', () async {
      final runner = CommandRunner<void>(
        'test',
        'InitWorkspaceCommand Test',
      )..addCommand(InitWorkspaceCommand(ggLog: ggLog, rootPath: tempDir.path));
      final wsPath = path.join(tempDir.path, ggMultiOceanFolder);
      expect(Directory(wsPath).existsSync(), isFalse);

      await runner.run(['workspace']);
      expect(messages.any((m) => m.contains('initialized at')), isTrue);
      expect(Directory(wsPath).existsSync(), isTrue);
    });

    test(
      'should not recreate if already exists, and log accordingly',
      () async {
        final wsPath = path.join(tempDir.path, ggMultiOceanFolder);
        Directory(wsPath).createSync(recursive: true);
        final runner = CommandRunner<void>('test', 'InitWorkspaceCommand Test')
          ..addCommand(
            InitWorkspaceCommand(ggLog: ggLog, rootPath: tempDir.path),
          );

        await runner.run(['workspace']);

        expect(messages[0], contains('ocean already exists at:'));
        expect(messages[0], contains(ggMultiOceanFolder));
        expect(Directory(wsPath).existsSync(), isTrue);
      },
    );

    test('should not allow init inside non-empty directory', () async {
      // Arrange:
      final nonEmptyDir = Directory(path.join(tempDir.path, 'not_empty'));
      nonEmptyDir.createSync(recursive: true);
      File(
        path.join(nonEmptyDir.path, 'some_file.txt'),
      ).writeAsStringSync('dummy');
      final runner = CommandRunner<void>('test', 'InitWorkspaceCommand Test')
        ..addCommand(
          InitWorkspaceCommand(ggLog: ggLog, rootPath: nonEmptyDir.path),
        );
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
        final runner =
            CommandRunner<void>('test', 'InitWorkspaceCommand Nested')
              ..addCommand(
                InitWorkspaceCommand(ggLog: ggLog, rootPath: childDir.path),
              );
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
      },
    );

    test('prints help when --help is passed', () async {
      final runner = CommandRunner<void>(
        'test',
        'InitWorkspaceCommand Help',
      )..addCommand(InitWorkspaceCommand(ggLog: ggLog, rootPath: tempDir.path));

      expect(() async {
        await runner.run(['workspace', '--help']);
      }, returnsNormally);
    });
  });
}
