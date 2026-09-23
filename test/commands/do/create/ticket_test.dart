// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_multi_core/gg_multi_core.dart';
import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_multi_workspace/src/commands/do/create/ticket.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('TicketCommand', () {
    late Directory tempDir;
    late CommandRunner<void> runner;
    final messages = <String>[];

    void ggLog(String msg) {
      messages.add(rmControls(msg));
    }

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync('ticket_test_');
      runner = CommandRunner<void>('test', 'TicketCommand Test')
        ..addCommand(
          TicketCommand(
            ggLog: ggLog,
            rootPath: tempDir.path,
            directoryFactory: (p) => Directory(p),
          ),
        );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    group('empties the trash on the way', () {
      test('and reports what it dropped', () async {
        // Creating a ticket is where the workspace is swept: an entry that
        // has been in the trash longer than Trash.maxAge goes.
        final stale = Directory(path.join(tempDir.path, '.trash', 'OLD-1'))
          ..createSync(recursive: true);
        final long = DateTime.now()
            .toUtc()
            .subtract(Trash.maxAge + const Duration(days: 1))
            .toIso8601String();
        File(path.join(tempDir.path, '.trash', Trash.indexFileName))
            .writeAsStringSync('{"OLD-1":"$long"}');

        await runner.run([
          'ticket',
          '--input',
          tempDir.path,
          'CDM-1',
          '-m',
          'x',
        ]);

        expect(stale.existsSync(), isFalse);
        expect(
          messages.any((m) => m.contains('Emptied 1 trash entry older than')),
          isTrue,
        );
      });

      test('but never at the cost of the ticket', () async {
        // A `.ocean` that is a file where a folder belongs makes the sweep
        // throw — the ticket is created regardless.
        Directory(path.join(tempDir.path, '.trash'))
            .createSync(recursive: true);
        File(path.join(tempDir.path, '.trash', '.ocean'))
            .writeAsStringSync('not a folder');

        await runner.run([
          'ticket',
          '--input',
          tempDir.path,
          'CDM-2',
          '-m',
          'x',
        ]);

        expect(
          messages.any((m) => m.contains('Could not empty the trash')),
          isTrue,
        );
        expect(
          File(path.join(tempDir.path, 'CDM-2', ticketJsonFileName))
              .existsSync(),
          isTrue,
        );
      });
    });

    test('creates folder and writes ticket.json file', () async {
      const issueId = 'CDM-128';
      const description = 'Fix some ugly bug';
      const ticketRelPath = issueId;

      await runner.run([
        'ticket',
        '--input',
        tempDir.path,
        issueId,
        '-m',
        description,
      ]);

      final ticketDir = Directory(path.join(tempDir.path, issueId));
      expect(ticketDir.existsSync(), isTrue);

      // Every ticket gets its trash folder right away.
      expect(
        Directory(path.join(tempDir.path, ggMultiTrashFolder, issueId))
            .existsSync(),
        isTrue,
      );

      final ticketFile = File(path.join(ticketDir.path, ticketJsonFileName));
      expect(ticketFile.existsSync(), isTrue);

      final content = ticketFile.readAsStringSync();
      final data = jsonDecode(content) as Map<String, dynamic>;
      expect(data['issue_id'], equals(issueId));
      expect(data['description'], equals(description));

      expect(
        messages.any((m) => m.contains('Created ticket $issueId')),
        isTrue,
      );
      expect(messages, [
        '✓ Created ticket CDM-128',
        '  Please run:',
        '    cd CDM-128',
        '    gg do add <repo1> <repo2> ...',
        '    code CDM-128.code-workspace',
      ]);
      expect(messages, contains('    cd $ticketRelPath'));
    });

    test('writes a VS Code workspace holding the ticket folder', () async {
      // `do code` must open something useful before the first `do add`.
      const issueId = 'CDM-129';

      await runner.run([
        'ticket',
        '--input',
        tempDir.path,
        issueId,
        '-m',
        'Fresh ticket',
      ]);

      final wsFile = File(
        path.join(tempDir.path, issueId, '$issueId.code-workspace'),
      );
      expect(wsFile.existsSync(), isTrue);
      final ws = jsonDecode(wsFile.readAsStringSync()) as Map<String, dynamic>;
      expect(
        (ws['folders'] as List<dynamic>).cast<Map<String, dynamic>>().map(
          (f) => f['path'] as String,
        ),
        <String>['.'],
      );
    });

    test('creates relative paths based on the execution directory', () async {
      const issueId = 'INSIDE-1';
      // The ticket is created from within another ticket of the same
      // workspace, so the `cd` command has to lead out of that one first.
      final otherTicket = Directory(path.join(tempDir.path, 'OTHER-1'))
        ..createSync(recursive: true);

      await runner.run(<String>[
        'ticket',
        '-m',
        'message',
        '--input',
        otherTicket.path,
        issueId,
      ]);

      // The new ticket is a sibling of the one it was created from — never a
      // folder inside it.
      final ticketDir = Directory(path.join(tempDir.path, issueId));
      expect(ticketDir.existsSync(), isTrue);

      expect(messages, [
        '✓ Created ticket INSIDE-1',
        '  Please run:',
        '    cd ${path.join('..', issueId)}',
        '    gg do add <repo1> <repo2> ...',
        '    code INSIDE-1.code-workspace',
      ]);
    });

    test('creates a ticket beside an existing legacy tickets folder', () async {
      // A workspace of an older gg still groups its tickets in a `tickets`
      // folder; new tickets are created in the root next to it all the same.
      final legacy = Directory(
        path.join(tempDir.path, ggMultiLegacyTicketFolder, 'OLD-1'),
      )..createSync(recursive: true);
      File(path.join(legacy.path, ticketJsonFileName))
          .writeAsStringSync('{"issue_id": "OLD-1"}');

      await runner.run(<String>[
        'ticket',
        '-m',
        'message',
        '--input',
        tempDir.path,
        'NEW-1',
      ]);

      expect(Directory(path.join(tempDir.path, 'NEW-1')).existsSync(), isTrue);
      expect(
        Directory(path.join(tempDir.path, ggMultiLegacyTicketFolder, 'NEW-1'))
            .existsSync(),
        isFalse,
      );
    });

    test('does not create ticket if it already exists', () async {
      const issueId = 'DUP-1';
      const description = 'duplicate ticket';
      const ticketRelPath = issueId;

      // First creation
      await runner.run([
        'ticket',
        '--input',
        tempDir.path,
        issueId,
        '-m',
        description,
      ]);
      final ticketDir = Directory(path.join(tempDir.path, issueId));
      final ticketFile = File(path.join(ticketDir.path, ticketJsonFileName));
      expect(ticketFile.existsSync(), isTrue);

      // Try to create same ticket again — an error, not a success exit.
      messages.clear();
      await expectLater(
        runner.run([
          'ticket',
          '--input',
          tempDir.path,
          issueId,
          '-m',
          description,
        ]),
        throwsA(
          isA<Exception>().having(
            (e) => rmControls(e.toString()),
            'message',
            contains('Ticket $issueId already exists at $ticketRelPath.'),
          ),
        ),
      );
      // Existing file still exists and was not modified again
      expect(ticketFile.existsSync(), isTrue);
      expect(messages, isEmpty);
    });

    test('refuses issue ids that are no single folder name and creates '
        'nothing', () async {
      final expected = <String, String>{
        '': 'must not be empty',
        '  ': 'must not be empty',
        'a/b': 'is a path',
        r'a\b': 'is a path',
        tempDir.path: 'is a path',
        'T1//': 'is a path',
      };
      for (final MapEntry(key: issueId, value: reason) in expected.entries) {
        await expectLater(
          runner.run(['ticket', '--input', tempDir.path, issueId, '-m', 'x']),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              contains(reason),
            ),
          ),
          reason: issueId,
        );
      }
      expect(tempDir.listSync(), isEmpty);
    });

    test('drops the trailing separator a tab completion appends', () async {
      await runner.run([
        'ticket',
        '--input',
        tempDir.path,
        'T5${path.separator}',
        '-m',
        'x',
      ]);

      expect(
        File(path.join(tempDir.path, 'T5', ticketJsonFileName)).existsSync(),
        isTrue,
      );
      expect(messages.first, '✓ Created ticket T5');
    });

    test('creates tickets/<id> as <id> in the workspace root, never as a new '
        'legacy ticket, and refuses a deeper path', () async {
      final legacy = Directory(
        path.join(tempDir.path, ggMultiLegacyTicketFolder),
      )..createSync();

      await runner.run([
        'ticket',
        '--input',
        tempDir.path,
        '$ggMultiLegacyTicketFolder/42/',
        '-m',
        'x',
      ]);

      expect(
        File(path.join(tempDir.path, '42', ticketJsonFileName)).existsSync(),
        isTrue,
      );
      expect(Directory(path.join(legacy.path, '42')).existsSync(), isFalse);
      expect(messages.first, '✓ Created ticket 42');

      await expectLater(
        runner.run([
          'ticket',
          '--input',
          tempDir.path,
          '$ggMultiLegacyTicketFolder/43/sub',
          '-m',
          'x',
        ]),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            contains('is a path'),
          ),
        ),
      );
      expect(Directory(path.join(tempDir.path, '43')).existsSync(), isFalse);
      expect(legacy.listSync(), isEmpty);
    });

    test('takes an empty folder prepared in the workspace root', () async {
      final prepared = Directory(path.join(tempDir.path, 'PREP-1'))
        ..createSync();

      await runner.run([
        'ticket',
        '--input',
        tempDir.path,
        'PREP-1',
        '-m',
        'x',
      ]);

      expect(
        File(path.join(prepared.path, ticketJsonFileName)).existsSync(),
        isTrue,
      );
    });

    test('refuses an issue id that starts with a dot', () async {
      // A hidden folder is never a ticket, so such a ticket would be lost.
      await expectLater(
        runner.run(['ticket', '--input', tempDir.path, '.foo', '-m', 'desc']),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            contains('hidden folders are never tickets'),
          ),
        ),
      );

      expect(Directory(path.join(tempDir.path, '.foo')).existsSync(), isFalse);
      expect(
        Directory(path.join(tempDir.path, ggMultiTrashFolder, '.foo'))
            .existsSync(),
        isFalse,
      );
    });

    test('refuses the issue id tickets, the legacy ticket folder, in any '
        'case', () async {
      for (final issueId in <String>[
        ggMultiLegacyTicketFolder,
        ggMultiLegacyTicketFolder.toUpperCase(),
      ]) {
        await expectLater(
          runner.run(['ticket', '--input', tempDir.path, issueId, '-m', 'x']),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              contains('is reserved for the folder older gg versions'),
            ),
          ),
          reason: issueId,
        );
      }

      expect(tempDir.listSync(), isEmpty);
    });

    test('refuses a name the root holds as a folder or a file that is no '
        'ticket, and writes nothing into it', () async {
      // What `gg do init workspace` instantiates in the workspace root.
      for (final name in <String>['doc', 'dna', 'scripts']) {
        final folder = Directory(path.join(tempDir.path, name))..createSync();
        File(path.join(folder.path, 'guide.md')).writeAsStringSync('# Guide');
      }
      final license = File(path.join(tempDir.path, 'LICENSE'))
        ..writeAsStringSync('license text');

      for (final name in <String>['doc', 'dna', 'scripts', 'LICENSE']) {
        await expectLater(
          runner.run(['ticket', '--input', tempDir.path, name, '-m', 'x']),
          throwsA(
            isA<Exception>().having(
              (e) => rmControls(e.toString()),
              'message',
              contains('$name already exists and is no ticket'),
            ),
          ),
          reason: name,
        );

        final target = path.join(tempDir.path, name);
        expect(
          File(path.join(target, ticketJsonFileName)).existsSync(),
          isFalse,
        );
        expect(
          File(path.join(target, '$name.code-workspace')).existsSync(),
          isFalse,
        );
        expect(
          Directory(path.join(tempDir.path, ggMultiTrashFolder, name))
              .existsSync(),
          isFalse,
        );
      }
      expect(license.readAsStringSync(), 'license text');
      expect(messages, isEmpty);
    });

    test('reports a legacy ticket as existing instead of creating a second '
        'one in the root', () async {
      // A legacy ticket of an older gg may lack a ticket.json.
      final legacy = Directory(
        path.join(tempDir.path, ggMultiLegacyTicketFolder, 'OLD-1'),
      )..createSync(recursive: true);

      await expectLater(
        runner.run(['ticket', '--input', tempDir.path, 'OLD-1', '-m', 'x']),
        throwsA(
          isA<Exception>().having(
            (e) => rmControls(e.toString()),
            'message',
            contains(
              'Ticket OLD-1 already exists at '
              '${path.join(ggMultiLegacyTicketFolder, 'OLD-1')}.',
            ),
          ),
        ),
      );

      expect(messages, isEmpty);
      expect(Directory(path.join(tempDir.path, 'OLD-1')).existsSync(), isFalse);
      expect(
        File(path.join(legacy.path, ticketJsonFileName)).existsSync(),
        isFalse,
      );
    });

    test('throws UsageException when missing issue id', () async {
      await expectLater(
        runner.run(['ticket', '--input', tempDir.path, '-m', 'desc']),
        throwsA(isA<UsageException>()),
      );
    });

    test('prints help when --help is passed', () async {
      final output = await capturePrint(
        code: () async {
          await runner.run(['ticket', '--help']);
        },
      );
      expect(
        output.first,
        contains('Create a ticket folder with its ticket data'),
      );
    });
  });
}
