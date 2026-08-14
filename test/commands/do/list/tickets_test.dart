// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_multi_core/gg_multi_core.dart';
import 'package:gg_multi_workspace/src/commands/do/list/tickets.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('ListTicketsCommand', () {
    late Directory tempDir;
    late Directory ggMultiWorkspaceDir;
    late Directory ticketsDir;
    late CommandRunner<void> runner;
    final messages = <String>[];

    void ggLog(String m) => messages.add(rmControls(m));

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync('ticket_list_test');
      ggMultiWorkspaceDir = Directory(
        path.join(tempDir.path, 'ggMultiWorkspace'),
      )..createSync(recursive: true);
      // Tickets sit directly in the workspace root.
      ticketsDir = ggMultiWorkspaceDir;
      runner = CommandRunner<void>('test', 'Test ListTicketsCommand')
        ..addCommand(
          ListTicketsCommand(
            ggLog: ggLog,
            workspacePath: ggMultiWorkspaceDir.path,
          ),
        );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('lists tickets with name and description', () async {
      final t1dir = Directory(path.join(ticketsDir.path, 'T1'))..createSync();
      final t2dir = Directory(path.join(ticketsDir.path, 'T2'))..createSync();
      File(path.join(t1dir.path, ticketJsonFileName)).writeAsStringSync(
        jsonEncode({'issue_id': 'T1', 'description': 'Bugfix'}),
      );
      File(path.join(t2dir.path, ticketJsonFileName)).writeAsStringSync(
        jsonEncode({'issue_id': 'T2', 'description': 'Feature XY'}),
      );
      await runner.run(['tickets']);
      expect(messages, contains('T1    Bugfix'));
      expect(messages, contains('T2    Feature XY'));
    });

    test('no tickets found when the workspace root is missing', () async {
      ggMultiWorkspaceDir.deleteSync(recursive: true);
      await runner.run(['tickets']);
      expect(messages, contains('No tickets found.'));
    });

    test('no tickets found when the workspace holds none', () async {
      // The root exists but has no ticket folders
      await runner.run(['tickets']);
      expect(messages, contains('No tickets found.'));
    });

    test('a folder without a ticket.json is no ticket', () async {
      // The workspace root holds more than tickets — `.ocean`, `.trash` and
      // whatever else the user keeps there. The ticket.json is what tells
      // them apart.
      Directory(path.join(ticketsDir.path, 'T3')).createSync();
      Directory(path.join(ticketsDir.path, '.ocean')).createSync();
      await runner.run(['tickets']);
      expect(messages, contains('No tickets found.'));
      expect(messages.any((m) => m.startsWith('T3')), isFalse);
    });

    test('lists the tickets of a legacy tickets folder too', () async {
      final legacy = Directory(
        path.join(ggMultiWorkspaceDir.path, ggMultiLegacyTicketFolder, 'T9'),
      )..createSync(recursive: true);
      File(path.join(legacy.path, ticketJsonFileName)).writeAsStringSync(
        jsonEncode({'issue_id': 'T9', 'description': 'Old home'}),
      );
      await runner.run(['tickets']);
      expect(messages, contains('T9    Old home'));
    });

    test('invalid JSON in ticket.json logs parsing error', () async {
      final tdir = Directory(path.join(ticketsDir.path, 'T4'))..createSync();
      File(path.join(tdir.path, ticketJsonFileName))
          .writeAsStringSync('{ this is not valid json');
      await runner.run(['tickets']);
      expect(
        messages.any(
          (m) => m.startsWith('Error parsing ticket.json for ticket T4:'),
        ),
        isTrue,
      );
    });

    test('--help is allowed', () async {
      final output = await capturePrint(
        code: () async {
          await runner.run(['tickets', '--help']);
        },
      );
      expect(output.first, contains('List tickets and their descriptions'));
    });
  });
}
