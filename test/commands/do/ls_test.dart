// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_multi_core/gg_multi_core.dart';
import 'package:gg_multi_workspace/src/commands/do/ls.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('ListCommand', () {
    late Directory tempDir;
    late Directory oceanDir;
    final messages = <String>[];

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync('list_test');
      oceanDir = Directory(path.join(tempDir.path, ggMultiOceanFolder))
        ..createSync(recursive: true);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('should show all sub commands', () async {
      final listCommand = ListCommand(
        ggLog: messages.add,
        workspacePath: oceanDir.path,
      );
      // Update the directory path to use the correct path separator
      final commandsDir = Directory(
        path.join('lib', 'src', 'commands', 'do', 'list'),
      );
      final (subCommands, errorMessage) = await missingSubCommands(
        directory: commandsDir,
        command: listCommand,
      );

      expect(subCommands, isEmpty, reason: errorMessage);
    });

    test('prints help message when --help is passed', () async {
      final runner = CommandRunner<void>('test', 'ListCommand Help');
      runner.addCommand(
        ListCommand(ggLog: (_) {}, workspacePath: oceanDir.path),
      );
      final output = await capturePrint(
        code: () async {
          await runner.run(['ls', '--help']);
        },
      );
      expect(
        output.first,
        contains('List repos, organizations or dependencies'),
      );
    });
  });
}
