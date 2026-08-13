// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_multi_workspace/src/commands/do/init.dart';
import 'package:test/test.dart';

void main() {
  group('InitCommand', () {
    final messages = <String>[];

    test('should register all subcommands', () async {
      final initCommand = InitCommand(ggLog: messages.add);
      final commandsDir = Directory(
        'lib${Platform.pathSeparator}src${Platform.pathSeparator}'
        'commands${Platform.pathSeparator}do${Platform.pathSeparator}init',
      );
      final (subCommands, errorMessage) = await missingSubCommands(
        directory: commandsDir,
        command: initCommand,
      );
      expect(subCommands, isEmpty, reason: errorMessage);
    });

    test('has the name and description of the group', () {
      final initCommand = InitCommand(ggLog: messages.add);
      expect(initCommand.name, 'init');
      expect(initCommand.description, 'Initialize workspace or agent files');
    });

    test('prints help message including workspace and claude', () async {
      final runner = CommandRunner<void>('test', 'InitCommand Help')
        ..addCommand(InitCommand(ggLog: (_) {}));

      final output = await capturePrint(
        code: () async {
          await runner.run(['init', '--help']);
        },
      );

      expect(output.join('\n'), contains('workspace'));
      expect(output.join('\n'), contains('claude'));
    });
  });
}
