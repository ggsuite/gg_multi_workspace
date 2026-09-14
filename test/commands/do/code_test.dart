// @license
// Copyright (c) ggsuite
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
    late Directory execDir;
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
      execDir = Directory.systemTemp.createTempSync('exec_path_');
      messages = <String>[];
      launched = <List<Object?>>[];
      runner = CommandRunner<void>('test', 'test')
        ..addCommand(
          CodeCommand(
            executionPath: execDir.path,
            ggLog: ggLog,
            rootPath: tempRoot.path,
            directoryFactory: Directory.new,
            launcher: VSCodeLauncher(processStarter: fakeStarter),
          ),
        );
    });

    tearDown(() {
      for (final dir in <Directory>[tempRoot, execDir]) {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
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

    test('opens a ticket in the root, recognized by its ticket.json', () async {
      final tdir = Directory(path.join(tempRoot.path, 'T9'))..createSync();
      File(path.join(tdir.path, ticketJsonFileName)).writeAsStringSync('{}');

      await runner.run(<String>['code', 'T9']);

      expect(launched.single[1], path.join(tdir.path, 'T9.code-workspace'));
    });

    test('never opens a hidden or a plain folder of the root, and says '
        'why', () async {
      // What a DNA instantiates in the workspace root — `.github` even with a
      // ticket.json.
      final github = Directory(path.join(tempRoot.path, '.github'))
        ..createSync();
      File(path.join(github.path, ticketJsonFileName)).writeAsStringSync('{}');
      Directory(path.join(tempRoot.path, '.claude')).createSync();
      Directory(path.join(tempRoot.path, 'doc')).createSync();

      for (final name in <String>['.github', '.claude']) {
        await expectLater(
          runner.run(<String>['code', name]),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              contains('"$name" starts with a dot'),
            ),
          ),
        );
      }
      await runner.run(<String>['code', 'doc']);
      expect(messages.last, contains('doc is no ticket: '));
      expect(messages.last, contains('holds no $ticketJsonFileName.'));
      expect(launched, isEmpty);
    });

    test('throws for empty ticket names and tickets', () async {
      Directory(path.join(tempRoot.path, ggMultiLegacyTicketFolder, 'T1'))
          .createSync(recursive: true);

      final expected = <String, String>{
        '': 'must not be empty',
        '  ': 'must not be empty',
        ggMultiLegacyTicketFolder: 'is reserved',
        '${ggMultiLegacyTicketFolder.toUpperCase()}/': 'is reserved',
        '$ggMultiLegacyTicketFolder/.github': 'is reserved',
      };
      for (final MapEntry(key: target, value: reason) in expected.entries) {
        await expectLater(
          runner.run(<String>['code', target]),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              contains(reason),
            ),
          ),
          reason: target,
        );
      }
      expect(launched, isEmpty);
    });

    test('throws for an absolute path and says so', () async {
      final ticket = Directory(path.join(tempRoot.path, 'T1'))..createSync();
      File(path.join(ticket.path, ticketJsonFileName)).writeAsStringSync('{}');

      for (final target in <String>['/', '/T1', r'\T1', ticket.path]) {
        await expectLater(
          runner.run(<String>['code', target]),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              contains('"$target" is an absolute path'),
            ),
          ),
          reason: target,
        );
      }
      expect(launched, isEmpty);
    });

    test('ignores the trailing separator a tab completion appends', () async {
      final tdir = Directory(path.join(tempRoot.path, 'T9'))..createSync();
      File(path.join(tdir.path, ticketJsonFileName)).writeAsStringSync('{}');

      await runner.run(<String>['code', 'T9${path.separator}']);

      expect(launched.single[1], path.join(tdir.path, 'T9.code-workspace'));
    });

    test('tolerates repeated and trailing separators and takes an empty '
        'repo segment for no repo', () async {
      final tdir = Directory(path.join(tempRoot.path, 'T9'))..createSync();
      File(path.join(tdir.path, ticketJsonFileName)).writeAsStringSync('{}');
      final repo = Directory(path.join(tdir.path, 'MyRepo'))..createSync();
      File(path.join(repo.path, 'pubspec.yaml')).writeAsStringSync('name: x');

      final expected = <String, String>{
        'T9//': path.join(tdir.path, 'T9.code-workspace'),
        r'T9\\': path.join(tdir.path, 'T9.code-workspace'),
        'T9//MyRepo': repo.path,
        'T9/MyRepo/': repo.path,
        r'T9\MyRepo\\': repo.path,
      };
      for (final MapEntry(key: target, value: opened) in expected.entries) {
        launched.clear();
        await runner.run(<String>['code', target]);
        expect(launched.single[1], opened, reason: target);
      }
    });

    test('opens a legacy ticket named tickets/<ticket>/ the way the tab '
        'completion in the workspace root offers it', () async {
      final legacy = Directory(
        path.join(tempRoot.path, ggMultiLegacyTicketFolder, 'L1'),
      )..createSync(recursive: true);

      for (final target in <String>[
        '$ggMultiLegacyTicketFolder/L1/',
        '$ggMultiLegacyTicketFolder/L1',
        '${ggMultiLegacyTicketFolder.toUpperCase()}\\L1\\',
        '$ggMultiLegacyTicketFolder//L1//',
      ]) {
        launched.clear();
        await runner.run(<String>['code', target]);
        expect(
          launched.single[1],
          path.join(legacy.path, 'L1.code-workspace'),
          reason: target,
        );
      }

      // Only one ticket is named that way, no repo inside it.
      launched.clear();
      await expectLater(
        runner.run(<String>['code', '$ggMultiLegacyTicketFolder/L1/repo']),
        throwsA(isA<UsageException>()),
      );
      expect(launched, isEmpty);
    });

    test('does not take a closed ticket in the trash for the ticket of the '
        'cwd', () async {
      final closed = Directory(
        path.join(tempRoot.path, ggMultiTrashFolder, 'T1'),
      )..createSync(recursive: true);
      File(path.join(closed.path, ticketJsonFileName)).writeAsStringSync('{}');

      final localRunner = CommandRunner<void>('test', 'test')
        ..addCommand(
          CodeCommand(
            ggLog: ggLog,
            rootPath: tempRoot.path,
            executionPath: closed.path,
            directoryFactory: Directory.new,
            launcher: VSCodeLauncher(processStarter: fakeStarter),
          ),
        );

      await expectLater(
        localRunner.run(<String>['code']),
        throwsA(isA<UsageException>()),
      );
      expect(launched, isEmpty);
    });

    test('opens workspace file when ticket exists but is empty', () async {
      Directory(path.join(tempRoot.path, ggMultiLegacyTicketFolder, 'T1'))
          .createSync(recursive: true);

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
      File(path.join(r.path, 'pubspec.yaml'))
          .writeAsStringSync('name: SlashRepo');
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
      File(path.join(r.path, 'pubspec.yaml'))
          .writeAsStringSync('name: OrgRepo');

      await runner.run(<String>['code', 'T_ORG/OrgRepo']);

      expect(launched.length, 1);
      expect(launched[0][1], r.path);
      expect(messages.last, contains('✓ Opened OrgRepo'));
    });

    test('logs error when specified repo missing', () async {
      Directory(path.join(tempRoot.path, ggMultiLegacyTicketFolder, 'T4'))
          .createSync(recursive: true);
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
