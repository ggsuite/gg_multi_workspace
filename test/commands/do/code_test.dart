// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_multi_core/gg_multi_core.dart';
import 'package:gg_multi_workspace/src/backend/vscode_launcher.dart';
import 'package:gg_multi_workspace/src/commands/do/code.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('CodeCommand', () {
    late Directory tempRoot;
    late List<String> messages;
    late List<List<Object?>> launched;
    late CommandRunner<void> runner;

    Future<void> fakeStarter(
      String exe,
      List<String> args, {
      bool runInShell = false,
    }) async {
      launched.add(<Object?>[exe, ...args, runInShell]);
    }

    void ggLog(String m) => messages.add(rmControls(m));

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('code_test_');
      final execPath = Directory.systemTemp.createTempSync('exec_path_').path;
      messages = <String>[];
      launched = <List<Object?>>[];
      runner = CommandRunner<void>('test', 'test')
        ..addCommand(
          CodeCommand(
            executionPath: execPath,
            ggLog: ggLog,
            rootPath: tempRoot.path,
            directoryFactory: Directory.new,
            launcher: VSCodeLauncher(processStarter: fakeStarter),
          ),
        );
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('throws UsageException when missing args', () {
      expect(
        () => runner.run(<String>['code']),
        throwsA(isA<UsageException>()),
      );
    });

    test('logs not found when ticket missing', () async {
      await runner.run(<String>['code', 'TCKT']);
      expect(messages.last, contains('Ticket TCKT not found at'));
    });

    test('opens workspace file when ticket exists but is empty', () async {
      Directory(
        path.join(tempRoot.path, ggMultiLegacyTicketFolder, 'T1'),
      ).createSync(recursive: true);

      await runner.run(<String>['code', 'T1']);

      expect(launched.length, 1);
      expect(launched[0][0], 'code');
      final expectedWorkspace = path.join(
        tempRoot.path,
        ggMultiLegacyTicketFolder,
        'T1',
        'T1.code-workspace',
      );
      expect(launched[0][1], expectedWorkspace);
      expect(launched[0][2], isTrue);
      expect(messages.last, contains('✓ Opened workspace T1.code-workspace'));
    });

    test('opens workspace file for ticket with repos', () async {
      final tdir = Directory(
        path.join(tempRoot.path, ggMultiLegacyTicketFolder, 'T2'),
      )..createSync(recursive: true);
      final a = Directory(path.join(tdir.path, 'A'))..createSync();
      File(path.join(a.path, 'pubspec.yaml')).writeAsStringSync('name: A');
      final b = Directory(path.join(tdir.path, 'B'))..createSync();
      File(path.join(b.path, 'pubspec.yaml')).writeAsStringSync('name: B');

      await runner.run(<String>['code', 'T2']);

      expect(launched.length, 1);
      expect(launched[0][0], 'code');
      final expectedWorkspace = path.join(tdir.path, 'T2.code-workspace');
      expect(launched[0][1], expectedWorkspace);
      expect(launched[0][2], isTrue);
      expect(messages.last, contains('✓ Opened workspace T2.code-workspace'));
    });

    test('opens single repo when specified', () async {
      final tdir = Directory(
        path.join(tempRoot.path, ggMultiLegacyTicketFolder, 'T3'),
      )..createSync(recursive: true);
      final r = Directory(path.join(tdir.path, 'MyRepo'))..createSync();
      File(path.join(r.path, 'pubspec.yaml')).writeAsStringSync('name: MyRepo');
      await runner.run(<String>['code', 'T3/MyRepo']);

      expect(launched.length, 1);
      expect(launched[0][0], 'code');
      expect(launched[0][1], path.join(tdir.path, 'MyRepo'));
      expect(launched[0][2], isTrue);
      expect(messages.last, contains('✓ Opened MyRepo'));
    });

    test('opens single repo when specified with backslash separator', () async {
      final tdir = Directory(
        path.join(tempRoot.path, ggMultiLegacyTicketFolder, 'T5'),
      )..createSync(recursive: true);
      final r = Directory(path.join(tdir.path, 'SlashRepo'))..createSync();
      File(
        path.join(r.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: SlashRepo');
      await runner.run(<String>['code', 'T5\\SlashRepo']);

      expect(launched.length, 1);
      expect(launched[0][0], 'code');
      expect(launched[0][1], path.join(tdir.path, 'SlashRepo'));
      expect(launched[0][2], isTrue);
      expect(messages.last, contains('✓ Opened SlashRepo at'));
    });

    test('opens a repo that sits in an organization folder', () async {
      // `<ticket>/<repo>` addresses the repo wherever it is in the ticket.
      final tdir = Directory(
        path.join(tempRoot.path, ggMultiLegacyTicketFolder, 'T_ORG'),
      )..createSync(recursive: true);
      final r = Directory(path.join(tdir.path, 'ggsuite', 'OrgRepo'))
        ..createSync(recursive: true);
      File(
        path.join(r.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: OrgRepo');

      await runner.run(<String>['code', 'T_ORG/OrgRepo']);

      expect(launched.length, 1);
      expect(launched[0][1], r.path);
      expect(messages.last, contains('✓ Opened OrgRepo'));
    });

    test('logs error when specified repo missing', () async {
      Directory(
        path.join(tempRoot.path, ggMultiLegacyTicketFolder, 'T4'),
      ).createSync(recursive: true);
      await runner.run(<String>['code', 'T4/NoRepo']);
      expect(
        messages.last,
        contains('Repository NoRepo not found in ticket T4 at'),
      );
      expect(launched, isEmpty);
    });

    test('handles --help without throwing', () async {
      await runner.run(<String>['code', '--help']);
    });

    test('throws UsageException on bad format', () {
      expect(
        () => runner.run(<String>['code', 'too/many/parts']),
        throwsA(isA<UsageException>()),
      );
    });

    test('opens workspace inside ticket dir when no args', () async {
      // Create a ticket folder under the temp root.
      final ticketDir = Directory(
        path.join(tempRoot.path, ggMultiLegacyTicketFolder, 'T_noArgs'),
      )..createSync(recursive: true);
      final a = Directory(path.join(ticketDir.path, 'A'))..createSync();
      File(path.join(a.path, 'pubspec.yaml')).writeAsStringSync('name: A');
      final b = Directory(path.join(ticketDir.path, 'B'))..createSync();
      File(path.join(b.path, 'pubspec.yaml')).writeAsStringSync('name: B');

      // Here we must call CodeCommand with executionPath = ticketDir.path.
      final localRunner = CommandRunner<void>('test', 'test')
        ..addCommand(
          CodeCommand(
            ggLog: ggLog,
            rootPath: tempRoot.path,
            executionPath: ticketDir.path,
            directoryFactory: Directory.new,
            launcher: VSCodeLauncher(processStarter: fakeStarter),
          ),
        );

      await localRunner.run(<String>['code']);

      expect(launched.length, 1);
      expect(launched[0][0], 'code');
      final expectedWorkspace = path.join(
        ticketDir.path,
        'T_noArgs.code-workspace',
      );
      expect(launched[0][1], expectedWorkspace);
      expect(launched[0][2], isTrue);
      expect(messages, contains('✓ Opened workspace T_noArgs.code-workspace'));
    });
  });
}
