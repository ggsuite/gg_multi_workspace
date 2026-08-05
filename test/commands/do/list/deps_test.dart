// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_multi_core/gg_multi_core.dart';
import 'package:gg_multi_workspace/src/commands/do/list/deps.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('ListDepsCommand', () {
    late Directory tempDir;
    late Directory oceanWorkspace;
    final messages = <String>[];

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync('list_deps_test');
      oceanWorkspace = Directory(path.join(tempDir.path, ggMultiOceanFolder))
        ..createSync(recursive: true);
      // Create a project folder 'project123' inside ocean
      final projectDir = Directory(path.join(oceanWorkspace.path, 'project123'))
        ..createSync(recursive: true);
      const pubspecContent = '''
name: project123
version: 1.0.0
dependencies:
  json_dart: ^3.5.2
dev_dependencies:
  json_serializer: ^1.4.2
''';
      File(
        path.join(projectDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(pubspecContent);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('lists dependencies from project pubspec.yaml', () async {
      final runner = CommandRunner<void>('test', 'Test ListDepsCommand');
      runner.addCommand(
        ListDepsCommand(
          ggLog: messages.add,
          workspacePath: oceanWorkspace.path,
        ),
      );

      await runner.run(['deps', 'project123', '--depth=1']);

      expect(messages[0], 'project123 v.1.0.0 (dart)');
      expect(messages.any((msg) => msg.contains('json_dart')), isTrue);
      expect(messages.any((msg) => msg.contains('^3.5.2')), isTrue);
      expect(
        messages.any((msg) => msg.contains('dev:json_serializer')),
        isTrue,
      );
      expect(messages.any((msg) => msg.contains('^1.4.2')), isTrue);
    });

    test('also lists package.json dependencies for a bridge', () async {
      // project123 already has a pubspec.yaml (from setUp); adding a
      // package.json turns it into a cross-language bridge.
      File(
        path.join(oceanWorkspace.path, 'project123', 'package.json'),
      ).writeAsStringSync(
        '{"name":"project123","version":"1.0.0",'
        '"dependencies":{"left_pad":"^1.0.0"}}',
      );

      final runner = CommandRunner<void>('test', 'Test ListDepsCommand');
      runner.addCommand(
        ListDepsCommand(
          ggLog: messages.add,
          workspacePath: oceanWorkspace.path,
        ),
      );

      await runner.run(['deps', 'project123']);

      // Dart side still listed.
      expect(messages[0], 'project123 v.1.0.0 (dart)');
      expect(messages.any((m) => m.contains('json_dart')), isTrue);
      // TypeScript side now listed too.
      expect(
        messages.any(
          (m) => m.contains('left_pad') && m.contains('(typescript)'),
        ),
        isTrue,
      );
    });

    test('logs an error for a malformed package.json', () async {
      File(
        path.join(oceanWorkspace.path, 'project123', 'package.json'),
      ).writeAsStringSync('{ not valid json');

      final runner = CommandRunner<void>('test', 'Test ListDepsCommand');
      runner.addCommand(
        ListDepsCommand(
          ggLog: messages.add,
          workspacePath: oceanWorkspace.path,
        ),
      );

      await runner.run(['deps', 'project123']);

      expect(
        messages.any((m) => m.contains('Error parsing package.json')),
        isTrue,
      );
    });

    test('prints help message when --help is passed', () async {
      final runner = CommandRunner<void>('test', 'Test ListDepsCommand');
      runner.addCommand(
        ListDepsCommand(
          ggLog: messages.add,
          workspacePath: oceanWorkspace.path,
        ),
      );
      final output = await capturePrint(
        code: () async {
          await runner.run(['deps', '--help']);
        },
      );
      expect(output.first, contains('List the dependencies of an ocean repo'));
    });

    test(
      'throws UsageException when target repository parameter is missing',
      () async {
        final runner = CommandRunner<void>('test', 'Test Missing Target');
        runner.addCommand(
          ListDepsCommand(
            ggLog: messages.add,
            workspacePath: oceanWorkspace.path,
          ),
        );
        await expectLater(runner.run(['deps']), throwsA(isA<UsageException>()));
      },
    );
  });
}
