// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
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
      ticketsDir = Directory(
        path.join(ggMultiWorkspaceDir.path, ggMultiTicketFolder),
      )..createSync(recursive: true);
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
      File(path.join(t1dir.path, '.ticket')).writeAsStringSync(
        jsonEncode({'issue_id': 'T1', 'description': 'Bugfix'}),
      );
      File(path.join(t2dir.path, '.ticket')).writeAsStringSync(
        jsonEncode({'issue_id': 'T2', 'description': 'Feature XY'}),
      );
      await runner.run(['tickets']);
      expect(messages, contains('T1    Bugfix'));
      expect(messages, contains('T2    Feature XY'));
    });

    test('no tickets found when tickets folder is missing', () async {
      ticketsDir.deleteSync(recursive: true);
      await runner.run(['tickets']);
      expect(messages, contains('No tickets found.'));
    });

    test('no tickets found when tickets folder is empty', () async {
      // ticketsDir exists but has no subfolders
      await runner.run(['tickets']);
      expect(messages, contains('No tickets found.'));
    });

    test('missing .ticket file logs error and skips', () async {
      Directory(path.join(ticketsDir.path, 'T3')).createSync();
      await runner.run(['tickets']);
      expect(messages, contains('Missing .ticket file for ticket T3'));
      // Should not log an entry line for T3
      expect(messages.any((m) => m.startsWith('T3    ')), isFalse);
    });

    test('invalid JSON in .ticket logs parsing error', () async {
      final tdir = Directory(path.join(ticketsDir.path, 'T4'))..createSync();
      File(
        path.join(tdir.path, '.ticket'),
      ).writeAsStringSync('{ this is not valid json');
      await runner.run(['tickets']);
      expect(
        messages.any(
          (m) => m.startsWith('Error parsing .ticket for ticket T4:'),
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
