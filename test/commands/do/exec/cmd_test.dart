// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_multi_workspace/src/commands/do/exec/cmd.dart';
import 'package:gg_process/gg_process.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

class MockProcessRunner extends Mock {
  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool? runInShell,
  });
}

class FakeDirectory extends Fake implements Directory {}

/// Pretends gg runs on Windows.
class _WindowsPlatform extends GgPlatformDelegate {
  const _WindowsPlatform();

  @override
  String get operatingSystem => 'windows';
}

/// Pretends gg runs on a posix system.
class _PosixPlatform extends GgPlatformDelegate {
  const _PosixPlatform();

  @override
  String get operatingSystem => 'macos';
}

void main() {
  late Directory tempDir;
  late Directory ticketsDir;
  late Directory ticketDir;
  final messages = <String>[];

  setUpAll(() {
    registerFallbackValue(FakeDirectory());
  });

  void ggLog(String msg) => messages.add(rmControls(msg));

  setUp(() {
    messages.clear();
    tempDir = Directory.systemTemp.createTempSync('do_maintain_exec_test_');
    ticketsDir = Directory(path.join(tempDir.path, 'tickets'))..createSync();
    ticketDir = Directory(path.join(ticketsDir.path, 'TICKX'))..createSync();
    // Create repositories with pubspec.yaml so SortedProcessingList finds them
    final aDir = Directory(path.join(ticketDir.path, 'A'))..createSync();
    File(path.join(aDir.path, 'pubspec.yaml')).writeAsStringSync('name: A');
    final bDir = Directory(path.join(ticketDir.path, 'B'))..createSync();
    File(path.join(bDir.path, 'pubspec.yaml')).writeAsStringSync('name: B');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('DoExecuteCommand (ticket-wide)', () {
    test('fails outside any ticket folder', () async {
      final runner = CommandRunner<void>('test', 'do maintain exec ticket')
        ..addCommand(DoExecuteCommand(ggLog: ggLog));
      await expectLater(
        () async => await runner.run(['cmd', '--input', tempDir.path, 'echo']),
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

    test('throws UsageException when missing command parameter', () async {
      final runner = CommandRunner<void>('test', 'do maintain exec usage')
        ..addCommand(DoExecuteCommand(ggLog: ggLog));

      await expectLater(
        () async => await runner.run(['cmd', '--input', ticketDir.path]),
        throwsA(isA<UsageException>()),
      );
    });

    test('logs when there are no repositories', () async {
      final emptyTicket = Directory(path.join(ticketsDir.path, 'EMPTY'))
        ..createSync();
      final runner = CommandRunner<void>('test', 'do maintain exec ticket')
        ..addCommand(DoExecuteCommand(ggLog: ggLog));
      await runner.run(['cmd', '--input', emptyTicket.path, 'echo', 'x']);
      expect(messages, contains('⚠️ No repos in this ticket'));
    });

    test('executes command successfully in all repos', () async {
      final mockRunner = MockProcessRunner();
      when(
        () => mockRunner(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));

      final runner = CommandRunner<void>('test', 'do maintain exec ticket')
        ..addCommand(
          DoExecuteCommand(ggLog: ggLog, processRunner: mockRunner.call),
        );
      await runner.run(['cmd', '--input', ticketDir.path, 'echo', 'hi']);

      // Verify calls for both repos with correct working directories
      verify(
        () => mockRunner('echo', [
          'hi',
        ], workingDirectory: path.join(ticketDir.path, 'A')),
      ).called(1);
      verify(
        () => mockRunner('echo', [
          'hi',
        ], workingDirectory: path.join(ticketDir.path, 'B')),
      ).called(1);

      expect(messages, [
        '\n'
            'A',
        'ok',
        '\n'
            'B',
        'ok',
        '\nCommand executed in all repos of TICKX\n',
      ]);
    });

    test('runs a quoted command line through the shell', () async {
      GgPlatformDelegate.current = const _PosixPlatform();
      addTearDown(() => GgPlatformDelegate.current = null);

      final mockRunner = MockProcessRunner();
      when(
        () => mockRunner(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, '', ''));

      final runner = CommandRunner<void>('test', 'do maintain exec ticket')
        ..addCommand(
          DoExecuteCommand(ggLog: ggLog, processRunner: mockRunner.call),
        );
      await runner.run(['cmd', '--input', ticketDir.path, 'dart fix --apply']);

      verify(
        () => mockRunner('sh', [
          '-c',
          'dart fix --apply',
        ], workingDirectory: path.join(ticketDir.path, 'A')),
      ).called(1);
      verify(
        () => mockRunner('sh', [
          '-c',
          'dart fix --apply',
        ], workingDirectory: path.join(ticketDir.path, 'B')),
      ).called(1);
    });

    test('runs a quoted command line through cmd on Windows', () async {
      GgPlatformDelegate.current = const _WindowsPlatform();
      addTearDown(() => GgPlatformDelegate.current = null);

      final mockRunner = MockProcessRunner();
      when(
        () => mockRunner(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, '', ''));

      final runner = CommandRunner<void>('test', 'do maintain exec ticket')
        ..addCommand(
          DoExecuteCommand(ggLog: ggLog, processRunner: mockRunner.call),
        );
      await runner.run(['cmd', '--input', ticketDir.path, 'dart fix --apply']);

      verify(
        () => mockRunner('cmd', [
          '/c',
          'dart fix --apply',
        ], workingDirectory: path.join(ticketDir.path, 'A')),
      ).called(1);
    });

    test('prints stderr of a succeeding command', () async {
      final mockRunner = MockProcessRunner();
      when(
        () => mockRunner(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, '', 'a warning'));

      final runner = CommandRunner<void>('test', 'do maintain exec ticket')
        ..addCommand(
          DoExecuteCommand(ggLog: ggLog, processRunner: mockRunner.call),
        );
      await runner.run(['cmd', '--input', ticketDir.path, 'echo', 'hi']);

      expect(messages, [
        '\nA',
        'a warning',
        '\nB',
        'a warning',
        '\nCommand executed in all repos of TICKX\n',
      ]);
    });

    test('collects failures and throws with summary', () async {
      final mockRunner = MockProcessRunner();
      when(
        () => mockRunner(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((invocation) async {
        final wd = invocation.namedArguments[#workingDirectory] as String;
        if (path.basename(wd) == 'B') {
          return ProcessResult(1, 1, '', 'error on B');
        }
        return ProcessResult(2, 0, 'ok', '');
      });

      final runner = CommandRunner<void>('test', 'do maintain exec ticket')
        ..addCommand(
          DoExecuteCommand(ggLog: ggLog, processRunner: mockRunner.call),
        );

      await expectLater(
        () async =>
            await runner.run(['cmd', '--input', ticketDir.path, 'echo']),
        throwsA(isA<Exception>()),
      );

      expect(messages, [
        '\nA',
        'ok',
        '\nB',
        // The reason is printed once, under the repo it belongs to.
        '✗ Failed to execute\nerror on B',
        '\nPlease fix the issues above.\n',
      ]);
    });
  });
}
