// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_multi_workspace/src/commands/do/import.dart';
import 'package:test/test.dart';

void main() {
  group('ImportCommand', () {
    final messages = <String>[];

    test('should register all subcommands', () async {
      final importCommand = ImportCommand(ggLog: messages.add);
      final commandsDir = Directory(
        'lib${Platform.pathSeparator}src${Platform.pathSeparator}'
        'commands${Platform.pathSeparator}do${Platform.pathSeparator}import',
      );
      final (subCommands, errorMessage) = await missingSubCommands(
        directory: commandsDir,
        command: importCommand,
      );
      expect(subCommands, isEmpty, reason: errorMessage);
    });

    test('has the name and description of the group', () {
      final importCommand = ImportCommand(ggLog: messages.add);
      expect(importCommand.name, 'import');
      expect(importCommand.description, 'Import something into the workspace');
    });

    test('prints help message including ticket', () async {
      final runner = CommandRunner<dynamic>('test', 'ImportCommand Help')
        ..addCommand(ImportCommand(ggLog: (_) {}));

      final output = await capturePrint(
        code: () async {
          await runner.run(['import', '--help']);
        },
      );

      expect(output.join('\n'), contains('ticket'));
    });
  });
}
