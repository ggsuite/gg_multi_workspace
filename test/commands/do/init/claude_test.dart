// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_multi_workspace/src/commands/do/init/claude.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late Directory ticketsDir;
  late Directory ticketDir;
  final messages = <String>[];

  void ggLog(String msg) => messages.add(rmControls(msg));

  setUp(() {
    messages.clear();
    tempDir = Directory.systemTemp.createTempSync('do_claude_ticket_test_');
    ticketsDir = Directory(path.join(tempDir.path, 'tickets'))..createSync();
    ticketDir = Directory(path.join(ticketsDir.path, 'TICKCL'))..createSync();

    final repoADir = Directory(path.join(ticketDir.path, 'A'))..createSync();
    File(path.join(repoADir.path, 'pubspec.yaml')).writeAsStringSync('name: A');
    File(path.join(repoADir.path, 'CLAUDE.md'))
        .writeAsStringSync('A architecture details');

    final repoBDir = Directory(path.join(ticketDir.path, 'B'))..createSync();
    File(path.join(repoBDir.path, 'pubspec.yaml')).writeAsStringSync('name: B');
    File(path.join(repoBDir.path, 'CLAUDE.md'))
        .writeAsStringSync('B architecture details');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('DoClaudeCommand (ticket-wide)', () {
    test('fails outside any ticket folder', () async {
      final runner = CommandRunner<void>('test', 'do claude ticket')
        ..addCommand(DoClaudeCommand(ggLog: ggLog));

      await expectLater(
        () async => await runner.run(['claude', '--input', tempDir.path]),
        throwsA(
          isA<Exception>().having(
            (e) => rmControls(e.toString()),
            'message',
            'Exception: Not inside a ticket folder',
          ),
        ),
      );

      expect(
        messages,
        contains('Please run this command inside a ticket folder.'),
      );
    });

    test('creates aggregated CLAUDE.md in the ticket directory', () async {
      final runner = CommandRunner<void>('test', 'do claude ticket')
        ..addCommand(DoClaudeCommand(ggLog: ggLog));

      await runner.run(['claude', '--input', ticketDir.path]);

      final ticketClaudeFile = File(path.join(ticketDir.path, 'CLAUDE.md'));
      expect(ticketClaudeFile.existsSync(), isTrue);

      final content = ticketClaudeFile.readAsStringSync();
      expect(content, contains('## Workspace Overview'));
      expect(content, contains('## Commands'));
      expect(content, contains('## Architecture'));
      expect(content, contains('### A Architecture'));
      expect(content, contains('A architecture details'));
      expect(content, contains('### B Architecture'));
      expect(content, contains('B architecture details'));

      expect(messages.any((m) => m.contains('Creating CLAUDE.md')), isTrue);
      expect(messages, contains('Execute claude code with:\nclaude'));
    });

    test('throws when a repository has no CLAUDE.md', () async {
      File(path.join(ticketDir.path, 'B', 'CLAUDE.md')).deleteSync();

      final runner = CommandRunner<void>('test', 'do claude ticket')
        ..addCommand(DoClaudeCommand(ggLog: ggLog));

      await expectLater(
        () async => await runner.run(['claude', '--input', ticketDir.path]),
        throwsA(
          isA<Exception>().having(
            (e) => rmControls(e.toString()),
            'message',
            'Exception: Please start claude and run /init in the repo B. '
                'Then execute this command again.',
          ),
        ),
      );
    });
  });
}
