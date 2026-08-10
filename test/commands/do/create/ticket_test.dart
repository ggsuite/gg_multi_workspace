// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
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
        Directory(path.join(tempDir.path, '.trash', issueId)).existsSync(),
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
      final legacy = Directory(path.join(tempDir.path, 'tickets', 'OLD-1'))
        ..createSync(recursive: true);
      File(
        path.join(legacy.path, ticketJsonFileName),
      ).writeAsStringSync('{"issue_id": "OLD-1"}');

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
        Directory(path.join(tempDir.path, 'tickets', 'NEW-1')).existsSync(),
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

      // Try to create same ticket again
      messages.clear();
      await runner.run([
        'ticket',
        '--input',
        tempDir.path,
        issueId,
        '-m',
        description,
      ]);
      // Existing file still exists and was not modified again
      expect(ticketFile.existsSync(), isTrue);

      expect(
        messages,
        contains('Error: Ticket $issueId already exists at $ticketRelPath'),
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
