// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_multi_core/gg_multi_core.dart';
import 'package:gg_multi_workspace/src/commands/do/rm/ticket.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('RemoveTicketCommand', () {
    late Directory tempDir; // workspace root
    late Directory ticketDir;
    final messages = <String>[];
    final coloredMessages = <String>[];
    final gitCalls = <String>[];

    void ggLog(String message) {
      coloredMessages.add(message);
      messages.add(rmControls(message));
    }

    Future<ProcessResult> processRunner(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
    }) async {
      gitCalls.add(
        '${path.basename(workingDirectory!)}: ${arguments.join(' ')}',
      );
      return ProcessResult(0, 0, '', '');
    }

    CommandRunner<void> runnerAt(String rootPath) {
      return CommandRunner<void>('test', 'RemoveTicketCommand Test')
        ..addCommand(
          RemoveTicketCommand(
            ggLog: ggLog,
            rootPath: rootPath,
            processRunner: processRunner,
          ),
        );
    }

    Directory repo(String org, String name) {
      final dir = Directory(path.join(ticketDir.path, org, name))
        ..createSync(recursive: true);
      File(
        path.join(dir.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: $name\nversion: 1.0.0\n');
      return dir;
    }

    setUp(() {
      messages.clear();
      coloredMessages.clear();
      gitCalls.clear();
      tempDir = Directory.systemTemp.createTempSync('rm_ticket_test_');
      ticketDir = Directory(path.join(tempDir.path, ggMultiTicketFolder, 'T88'))
        ..createSync(recursive: true);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('describes itself', () {
      final command = RemoveTicketCommand(ggLog: ggLog, rootPath: '/tmp');
      expect(command.name, 'ticket');
      expect(
        command.description,
        'Move tickets to the trash and delete their remote branches',
      );
      expect(command.invocation, 'gg do rm ticket [<ticket-id>...]');
    });

    test('refuses without a ticket name outside a ticket folder', () async {
      await expectLater(
        runnerAt(tempDir.path).run(['ticket']),
        throwsA(
          isA<Exception>().having(
            (e) => rmControls(e.toString()),
            'message',
            allOf(
              contains('needs a ticket'),
              contains('call it inside a ticket folder'),
              contains('gg do rm ticket <ticket-id>...'),
            ),
          ),
        ),
      );
      // Nothing was touched.
      expect(ticketDir.existsSync(), isTrue);
    });

    test('deletes the remote branches, moves the whole ticket to the trash '
        'and prints the way to the workspace root in blue', () async {
      repo('ggsuite', 'a');
      repo('ggsuite', 'b');
      File(
        path.join(ticketDir.path, 'T88.code-workspace'),
      ).writeAsStringSync('{}');

      await runnerAt(ticketDir.path).run(['ticket']);

      expect(gitCalls, [
        'a: push origin --delete T88',
        'b: push origin --delete T88',
      ]);

      final trash = path.join(tempDir.path, ggMultiTrashFolder, 'T88');
      expect(Directory(path.join(trash, 'ggsuite', 'a')).existsSync(), isTrue);
      expect(Directory(path.join(trash, 'ggsuite', 'b')).existsSync(), isTrue);
      expect(File(path.join(trash, 'T88.code-workspace')).existsSync(), isTrue);
      expect(ticketDir.existsSync(), isFalse);

      expect(
        messages.join('\n'),
        contains('Change to the workspace root with:'),
      );
      expect(coloredMessages.last, cCmd('  cd ${tempDir.absolute.path}'));
    });

    test('--no-delete-remote-branch keeps the remote branches', () async {
      repo('ggsuite', 'a');

      await runnerAt(
        ticketDir.path,
      ).run(['ticket', '--no-delete-remote-branch']);

      expect(gitCalls, isEmpty);
      expect(messages.join('\n'), contains('Kept remote branch T88 for a.'));
      expect(ticketDir.existsSync(), isFalse);
    });

    test('works from a sub-folder of the ticket', () async {
      final repoDir = repo('ggsuite', 'a');
      final subDir = Directory(path.join(repoDir.path, 'lib'))
        ..createSync(recursive: true);

      await runnerAt(subDir.path).run(['ticket']);

      expect(ticketDir.existsSync(), isFalse);
      expect(
        Directory(
          path.join(tempDir.path, ggMultiTrashFolder, 'T88', 'ggsuite', 'a'),
        ).existsSync(),
        isTrue,
      );
    });

    group('named tickets', () {
      /// Creates `<root>/tickets/<name>` holding one repo.
      Directory makeTicket(String name) {
        final dir = Directory(
          path.join(tempDir.path, ggMultiTicketFolder, name),
        )..createSync(recursive: true);
        final repoDir = Directory(path.join(dir.path, 'ggsuite', 'a'))
          ..createSync(recursive: true);
        File(
          path.join(repoDir.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: a\nversion: 1.0.0\n');
        return dir;
      }

      test('closes a ticket named on the command line', () async {
        final other = makeTicket('T99');

        // Invoked from the workspace root — no ticket in the cwd.
        await runnerAt(tempDir.path).run(['ticket', 'T99']);

        expect(other.existsSync(), isFalse);
        expect(
          Directory(
            path.join(tempDir.path, ggMultiTrashFolder, 'T99', 'ggsuite', 'a'),
          ).existsSync(),
          isTrue,
        );
        expect(gitCalls, ['a: push origin --delete T99']);
        // The ticket of the cwd is untouched — the name wins.
        expect(ticketDir.existsSync(), isTrue);
      });

      test(
        'closes several tickets in one call, each with its own heading',
        () async {
          final first = makeTicket('T90');
          final second = makeTicket('T91');

          await runnerAt(tempDir.path).run(['ticket', 'T90', 'T91']);

          expect(first.existsSync(), isFalse);
          expect(second.existsSync(), isFalse);
          // The branches are named after their own ticket.
          expect(gitCalls, [
            'a: push origin --delete T90',
            'a: push origin --delete T91',
          ]);
          // With more than one ticket each gets a heading.
          expect(messages.join('\n'), contains('T90'));
          expect(messages.join('\n'), contains('T91'));
        },
      );

      test('a name wins over the ticket the command runs in', () async {
        final other = makeTicket('T99');
        repo('ggsuite', 'a');

        await runnerAt(ticketDir.path).run(['ticket', 'T99']);

        expect(other.existsSync(), isFalse);
        expect(ticketDir.existsSync(), isTrue);
      });

      test('reports names that are no tickets and changes nothing', () async {
        final existing = makeTicket('T90');

        await expectLater(
          runnerAt(tempDir.path).run(['ticket', 'T90', 'ghost', 'phantom']),
          throwsA(
            isA<Exception>().having(
              (e) => rmControls(e.toString()),
              'message',
              allOf(
                contains('These tickets do not exist'),
                contains('ghost, phantom'),
              ),
            ),
          ),
        );

        // The check runs before the first removal — nothing was closed.
        expect(existing.existsSync(), isTrue);
        expect(gitCalls, isEmpty);
      });

      test(
        'forwards --no-delete-remote-branch to every named ticket',
        () async {
          makeTicket('T90');
          makeTicket('T91');

          await runnerAt(
            tempDir.path,
          ).run(['ticket', 'T90', 'T91', '--no-delete-remote-branch']);

          expect(gitCalls, isEmpty);
          expect(
            Directory(
              path.join(tempDir.path, ggMultiTrashFolder, 'T90'),
            ).existsSync(),
            isTrue,
          );
          expect(
            Directory(
              path.join(tempDir.path, ggMultiTrashFolder, 'T91'),
            ).existsSync(),
            isTrue,
          );
        },
      );
    });
  });
}
