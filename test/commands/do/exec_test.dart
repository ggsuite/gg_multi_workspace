// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_multi_workspace/src/commands/do/exec.dart';
import 'package:test/test.dart';

void main() {
  group('ExecCommand', () {
    final messages = <String>[];

    test('should register all subcommands', () async {
      final execCommand = ExecCommand(ggLog: messages.add);
      final commandsDir = Directory(
        'lib${Platform.pathSeparator}src${Platform.pathSeparator}'
        'commands${Platform.pathSeparator}do${Platform.pathSeparator}exec',
      );
      final (subCommands, errorMessage) = await missingSubCommands(
        directory: commandsDir,
        command: execCommand,
      );
      expect(subCommands, isEmpty, reason: errorMessage);
    });

    test('has the name and description of the group', () {
      final execCommand = ExecCommand(ggLog: messages.add);
      expect(execCommand.name, 'exec');
      expect(execCommand.description, 'Execute something in all ticket repos');
    });

    test('prints help message including cmd', () async {
      final runner = CommandRunner<void>('test', 'ExecCommand Help')
        ..addCommand(ExecCommand(ggLog: (_) {}));

      final output = await capturePrint(
        code: () async {
          await runner.run(['exec', '--help']);
        },
      );

      expect(output.join('\n'), contains('cmd'));
    });
  });
}
