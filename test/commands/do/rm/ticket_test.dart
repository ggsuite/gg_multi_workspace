// @license
// Copyright (c) ggsuite
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
      bool? runInShell,
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
      File(path.join(dir.path, 'pubspec.yaml'))
          .writeAsStringSync('name: $name\nversion: 1.0.0\n');
      return dir;
    }

    setUp(() {
      messages.clear();
      coloredMessages.clear();
      gitCalls.clear();
      tempDir = Directory.systemTemp.createTempSync('rm_ticket_test_');
      ticketDir = Directory(
        path.join(tempDir.path, ggMultiLegacyTicketFolder, 'T88'),
      )..createSync(recursive: true);
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
      File(path.join(ticketDir.path, 'T88.code-workspace'))
          .writeAsStringSync('{}');

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

      await runnerAt(ticketDir.path)
          .run(['ticket', '--no-delete-remote-branch']);

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

    group('never takes a hidden folder for the ticket of the cwd', () {
      Future<void> expectRefusedIn(Directory cwd) async {
        await expectLater(
          runnerAt(cwd.path).run(['ticket', '--no-delete-remote-branch']),
          throwsA(
            isA<Exception>().having(
              (e) => rmControls(e.toString()),
              'message',
              contains('needs a ticket'),
            ),
          ),
        );
      }

      test('not even one that holds a ticket.json', () async {
        final github = Directory(path.join(tempDir.path, '.github'))
          ..createSync();
        File(path.join(github.path, ticketJsonFileName))
            .writeAsStringSync('{}');
        final workflows = Directory(path.join(github.path, 'workflows'))
          ..createSync();

        await expectRefusedIn(workflows);

        expect(workflows.existsSync(), isTrue);
        expect(
          Directory(path.join(tempDir.path, ggMultiTrashFolder)).existsSync(),
          isFalse,
        );
      });

      test('nor a closed ticket in the trash', () async {
        final closed = Directory(
          path.join(tempDir.path, ggMultiTrashFolder, 'T5'),
        )..createSync(recursive: true);
        File(path.join(closed.path, ticketJsonFileName))
            .writeAsStringSync('{}');

        await expectRefusedIn(closed);

        expect(closed.existsSync(), isTrue);
      });
    });

    group('named tickets', () {
      /// Creates `<root>/tickets/<name>` holding one repo.
      Directory makeTicket(String name) {
        final dir = Directory(
          path.join(tempDir.path, ggMultiLegacyTicketFolder, name),
        )..createSync(recursive: true);
        final repoDir = Directory(path.join(dir.path, 'ggsuite', 'a'))
          ..createSync(recursive: true);
        File(path.join(repoDir.path, 'pubspec.yaml'))
            .writeAsStringSync('name: a\nversion: 1.0.0\n');
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
        'closes a ticket in the root, recognized by its ticket.json',
        () async {
          final ticket = Directory(path.join(tempDir.path, 'T77'))
            ..createSync();
          File(path.join(ticket.path, ticketJsonFileName))
              .writeAsStringSync('{}');

          await runnerAt(tempDir.path)
              .run(['ticket', 'T77', '--no-delete-remote-branch']);

          expect(ticket.existsSync(), isFalse);
          expect(
            Directory(path.join(tempDir.path, ggMultiTrashFolder, 'T77'))
                .existsSync(),
            isTrue,
          );
        },
      );

      test('refuses hidden names and plain folders of the root, even a hidden '
          'one holding a ticket.json, and moves nothing', () async {
        // What a DNA instantiates in the workspace root.
        final github = Directory(path.join(tempDir.path, '.github'))
          ..createSync();
        File(path.join(github.path, ticketJsonFileName))
            .writeAsStringSync('{}');
        final dartTool = Directory(path.join(tempDir.path, '.dart_tool'))
          ..createSync();
        final doc = Directory(path.join(tempDir.path, 'doc'))..createSync();

        await expectLater(
          runnerAt(tempDir.path).run([
            'ticket',
            '.github',
            '.dart_tool',
            'doc',
            '.',
            'ghost',
            '--no-delete-remote-branch',
          ]),
          throwsA(
            isA<Exception>().having(
              (e) => rmControls(e.toString()),
              'message',
              allOf(
                contains('".github" starts with a dot'),
                contains('".dart_tool" starts with a dot'),
                contains('"." starts with a dot'),
                contains('These are no tickets in ${tempDir.path}: doc.'),
                contains(
                  'These tickets do not exist in ${tempDir.path}: '
                  'ghost.',
                ),
              ),
            ),
          ),
        );

        expect(github.existsSync(), isTrue);
        expect(dartTool.existsSync(), isTrue);
        expect(doc.existsSync(), isTrue);
        expect(
          Directory(path.join(tempDir.path, ggMultiTrashFolder)).existsSync(),
          isFalse,
        );
      });

      test('refuses empty names and paths — which would address the root, '
          'the legacy tickets folder or any folder — and moves nothing '
          'and deletes no branch', () async {
        final elsewhere = Directory(path.join(tempDir.path, 'elsewhere'))
          ..createSync();
        // `tickets/<ticket>` names a ticket, one level deeper is a path.
        final legacyPath = path.join(ggMultiLegacyTicketFolder, 'T88', 'sub');

        await expectLater(
          runnerAt(tempDir.path).run([
            'ticket',
            '',
            '  ',
            tempDir.path,
            elsewhere.path,
            legacyPath,
            r'a\b',
            ggMultiLegacyTicketFolder,
            ggMultiLegacyTicketFolder.toUpperCase(),
          ]),
          throwsA(
            isA<Exception>().having(
              (e) => rmControls(e.toString()),
              'message',
              allOf(
                contains('A ticket name must not be empty.'),
                contains('"${tempDir.path}" is a path'),
                contains('"${elsewhere.path}" is a path'),
                contains('"$legacyPath" is a path'),
                contains(r'"a\b" is a path'),
                contains('"$ggMultiLegacyTicketFolder" is reserved'),
                contains(
                  '"${ggMultiLegacyTicketFolder.toUpperCase()}" is reserved',
                ),
              ),
            ),
          ),
        );

        // The legacy tickets folder with its ticket and every other folder
        // stay where they are.
        expect(ticketDir.existsSync(), isTrue);
        expect(elsewhere.existsSync(), isTrue);
        expect(
          Directory(path.join(tempDir.path, ggMultiTrashFolder)).existsSync(),
          isFalse,
        );
        expect(gitCalls, isEmpty);
      });

      test('ignores the trailing separator a tab completion appends', () async {
        final ticket = Directory(path.join(tempDir.path, 'T77'))..createSync();
        File(path.join(ticket.path, ticketJsonFileName))
            .writeAsStringSync('{}');

        await runnerAt(
          tempDir.path,
        ).run(['ticket', 'T77${path.separator}', '--no-delete-remote-branch']);

        expect(ticket.existsSync(), isFalse);
      });

      test('takes tickets/<ticket>/ — the tab completion in the root of a '
          'legacy workspace — for the legacy ticket', () async {
        final first = makeTicket('L1');
        final second = makeTicket('L2');

        await runnerAt(tempDir.path).run([
          'ticket',
          '$ggMultiLegacyTicketFolder/L1/',
          '${ggMultiLegacyTicketFolder.toUpperCase()}\\L2',
          '--no-delete-remote-branch',
        ]);

        expect(first.existsSync(), isFalse);
        expect(second.existsSync(), isFalse);
        for (final name in <String>['L1', 'L2']) {
          expect(
            Directory(path.join(tempDir.path, ggMultiTrashFolder, name))
                .existsSync(),
            isTrue,
            reason: name,
          );
        }
      });

      test(
        'forwards --no-delete-remote-branch to every named ticket',
        () async {
          makeTicket('T90');
          makeTicket('T91');

          await runnerAt(tempDir.path)
              .run(['ticket', 'T90', 'T91', '--no-delete-remote-branch']);

          expect(gitCalls, isEmpty);
          expect(
            Directory(path.join(tempDir.path, ggMultiTrashFolder, 'T90'))
                .existsSync(),
            isTrue,
          );
          expect(
            Directory(path.join(tempDir.path, ggMultiTrashFolder, 'T91'))
                .existsSync(),
            isTrue,
          );
        },
      );
    });
  });
}
