// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_multi_workspace/src/commands/do/create.dart';
import 'package:test/test.dart';

void main() {
  group('CreateCommand', () {
    final messages = <String>[];

    test('should register all subcommands', () async {
      final createCommand = CreateCommand(ggLog: messages.add);
      final commandsDir = Directory(
        'lib${Platform.pathSeparator}src${Platform.pathSeparator}'
        'commands${Platform.pathSeparator}do${Platform.pathSeparator}create',
      );
      final (subCommands, errorMessage) = await missingSubCommands(
        directory: commandsDir,
        command: createCommand,
      );
      expect(subCommands, isEmpty, reason: errorMessage);
    });

    test('prints help message including ticket', () async {
      final runner = CommandRunner<void>('test', 'CreateCommand Help')
        ..addCommand(CreateCommand(ggLog: (_) {}));

      final output = await capturePrint(
        code: () async {
          await runner.run(['create', '--help']);
        },
      );

      expect(
        output.last,
        contains('ticket'),
        reason: 'Help should mention the ticket subcommand.',
      );
    });
  });
}
