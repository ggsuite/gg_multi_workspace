// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_multi_workspace/src/commands/do/rm.dart';
import 'package:test/test.dart';

void main() {
  group('RmCommand', () {
    test('offers the repo and ticket subcommands', () async {
      final messages = <String>[];
      final runner = CommandRunner<void>('test', 'RmCommand Test')
        ..addCommand(RmCommand(ggLog: messages.add));

      await capturePrint(
        code: () async {
          await runner.run(['rm', '--help']);
        },
        ggLog: messages.add,
      );

      final help = messages.join('\n');
      expect(help, contains('Remove repos from a ticket, or a whole ticket'));
      expect(help, contains('repo'));
      expect(help, contains('ticket'));
    });
  });
}
