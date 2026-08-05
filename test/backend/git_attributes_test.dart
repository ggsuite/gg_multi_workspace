// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_multi_workspace/src/backend/git_attributes.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('installGitattributes (ticket-wide)', () {
    late Directory tempDir;
    late Directory ticketsDir;
    late Directory ticketDir;
    final messages = <String>[];
    late List<List<String>> processCalls;
    late List<String?> processWorkingDirs;
    late ProcessResult processResult;

    void ggLog(String msg) => messages.add(rmControls(msg));

    Future<ProcessResult> fakeRunner(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      bool runInShell = false,
      Map<String, String>? environment,
    }) async {
      processCalls.add(<String>[executable, ...arguments]);
      processWorkingDirs.add(workingDirectory);
      return processResult;
    }

    Future<void> callInstall(Directory dir) => installGitattributes(
      directory: dir,
      ggLog: ggLog,
      processRunner: fakeRunner,
    );

    setUp(() {
      messages.clear();
      processCalls = <List<String>>[];
      processWorkingDirs = <String?>[];
      processResult = ProcessResult(0, 0, '', '');
      tempDir = Directory.systemTemp.createTempSync(
        'do_install_gitattributes_ticket_test_',
      );
      ticketsDir = Directory(path.join(tempDir.path, 'tickets'))..createSync();
      ticketDir = Directory(path.join(ticketsDir.path, 'TICKG'))..createSync();
      for (final name in <String>['A', 'B']) {
        final repoDir = Directory(path.join(ticketDir.path, name))
          ..createSync();
        File(
          path.join(repoDir.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: $name');
        Directory(path.join(repoDir.path, '.git')).createSync();
      }
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('fails outside any ticket folder', () async {
      await expectLater(
        () async => callInstall(tempDir),
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

    test('logs when there are no repositories', () async {
      final emptyTicket = Directory(path.join(ticketsDir.path, 'EMPTY'))
        ..createSync();

      await callInstall(emptyTicket);

      expect(messages, contains('⚠️ No repos in this ticket'));
    });

    test('creates .gitattributes and configures merge driver', () async {
      await callInstall(ticketDir);

      for (final name in <String>['A', 'B']) {
        final file = File(path.join(ticketDir.path, name, '.gitattributes'));
        expect(file.existsSync(), isTrue);
        expect(
          file.readAsStringSync(),
          '$gitattributesCommonLines\npubspec.lock merge=ours\n',
        );
        expect(messages, contains('Created .gitattributes in $name.'));
        expect(messages, contains('Configured merge.ours driver in $name.'));
      }

      expect(processCalls, hasLength(2));
      for (final call in processCalls) {
        expect(call, <String>['git', 'config', 'merge.ours.driver', 'true']);
      }
      expect(processWorkingDirs, <String>[
        path.join(ticketDir.path, 'A'),
        path.join(ticketDir.path, 'B'),
      ]);

      expect(
        messages,
        contains(
          '✓ Ensured .gitattributes for all repositories in ticket TICKG.',
        ),
      );
    });

    test('writes no dart rules into a typescript repo', () async {
      final tsRepo = Directory(path.join(ticketDir.path, 'ts'))..createSync();
      File(
        path.join(tsRepo.path, 'package.json'),
      ).writeAsStringSync('{"name": "ts"}');
      File(path.join(tsRepo.path, 'pnpm-lock.yaml')).writeAsStringSync('');
      Directory(path.join(tsRepo.path, '.git')).createSync();

      await callInstall(ticketDir);

      expect(
        File(path.join(tsRepo.path, '.gitattributes')).readAsStringSync(),
        '$gitattributesCommonLines\npnpm-lock.yaml merge=ours\n',
      );
    });

    test(
      'writes the canonical lock file rule when no lock file exists',
      () async {
        final tsRepo = Directory(path.join(ticketDir.path, 'ts'))..createSync();
        File(
          path.join(tsRepo.path, 'package.json'),
        ).writeAsStringSync('{"name": "ts"}');
        Directory(path.join(tsRepo.path, '.git')).createSync();

        await callInstall(ticketDir);

        expect(
          File(path.join(tsRepo.path, '.gitattributes')).readAsStringSync(),
          '$gitattributesCommonLines\npackage-lock.json merge=ours\n',
        );
      },
    );

    test(
      'leaves an existing .gitattributes with all rules untouched',
      () async {
        final file = File(path.join(ticketDir.path, 'A', '.gitattributes'));
        const original =
            '# header\n'
            '* text=auto eol=lf\n'
            '.gg/gg.json merge=ours\n'
            'pubspec.lock merge=ours\n'
            'CHANGELOG.md merge=union\n';
        file.writeAsStringSync(original);
        final originalMtime = file.lastModifiedSync();

        await callInstall(ticketDir);

        expect(file.readAsStringSync(), original);
        expect(
          messages.any((m) => m == 'Created .gitattributes in A.'),
          isFalse,
        );
        expect(
          messages.any((m) => m == 'Updated .gitattributes in A.'),
          isFalse,
        );
        expect(file.lastModifiedSync(), originalMtime);
        // Merge driver is still configured.
        expect(messages, contains('Configured merge.ours driver in A.'));
      },
    );

    test('appends only the missing rules', () async {
      final fileA = File(path.join(ticketDir.path, 'A', '.gitattributes'))
        ..writeAsStringSync('*.png binary\n* text=auto eol=lf\n');
      final fileB = File(path.join(ticketDir.path, 'B', '.gitattributes'))
        ..writeAsStringSync('*.png binary');

      await callInstall(ticketDir);

      expect(
        fileA.readAsStringSync(),
        '*.png binary\n'
        '* text=auto eol=lf\n'
        '.gg/gg.json merge=ours\n'
        'CHANGELOG.md merge=union\n'
        'pubspec.lock merge=ours\n',
      );
      expect(
        fileB.readAsStringSync(),
        '*.png binary\n'
        '* text=auto eol=lf\n'
        '.gg/gg.json merge=ours\n'
        'CHANGELOG.md merge=union\n'
        'pubspec.lock merge=ours\n',
      );
      expect(messages, contains('Updated .gitattributes in A.'));
      expect(messages, contains('Updated .gitattributes in B.'));
    });

    test('skips merge driver config when .git is missing', () async {
      Directory(
        path.join(ticketDir.path, 'A', '.git'),
      ).deleteSync(recursive: true);

      await callInstall(ticketDir);

      expect(
        messages,
        contains(
          'Skipping merge.ours driver config for A because no '
          '.git directory was found.',
        ),
      );
      // Only B got the git config call.
      expect(processCalls, hasLength(1));
      expect(processWorkingDirs, <String>[path.join(ticketDir.path, 'B')]);
    });

    test('throws when git config fails', () async {
      processResult = ProcessResult(0, 1, '', 'boom');

      await expectLater(
        () async => callInstall(ticketDir),
        throwsA(
          isA<Exception>().having(
            (e) => rmControls(e.toString()),
            'message',
            contains('git config merge.ours.driver true failed in A'),
          ),
        ),
      );

      expect(
        messages.any(
          (m) => m.contains('Failed to configure merge.ours driver in A'),
        ),
        isTrue,
      );
    });

    test('processes every repo when called directly', () async {
      await callInstall(ticketDir);

      for (final name in <String>['A', 'B']) {
        final file = File(path.join(ticketDir.path, name, '.gitattributes'));
        expect(file.existsSync(), isTrue);
      }
      expect(processCalls, hasLength(2));
    });

    test('falls back to the real Process.run and list by default', () async {
      // An empty ticket exercises the default runner/list wiring without
      // actually spawning git.
      final emptyTicket = Directory(path.join(ticketsDir.path, 'EMPTY2'))
        ..createSync();

      await expectLater(
        installGitattributes(directory: emptyTicket, ggLog: ggLog),
        completes,
      );
      expect(messages, contains('⚠️ No repos in this ticket'));
    });
  });
}
