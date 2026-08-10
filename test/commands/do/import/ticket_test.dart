// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_multi_core/gg_multi_core.dart';
import 'package:args/command_runner.dart';
import 'package:gg_git/gg_git.dart' as gg_git;
import 'package:gg_multi_workspace/src/backend/git_handler.dart';
import 'package:gg_multi_workspace/src/commands/do/import/ticket.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

class _FakeDir extends Fake implements Directory {}

class MockGitHandler extends Mock implements GitHandler {}

class MockFetch extends Mock implements gg_git.Fetch {}

class MockCheckout extends Mock implements gg_git.Checkout {}

class MockShowFile extends Mock implements gg_git.ShowFile {}

class MockRemoteBranches extends Mock implements gg_git.RemoteBranches {}

class MockRemoteBranchExists extends Mock
    implements gg_git.RemoteBranchExists {}

class MockProcessRunner extends Mock {
  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    bool runInShell,
    Map<String, String>? environment,
  });
}

void main() {
  setUpAll(() => registerFallbackValue(_FakeDir()));

  late Directory tempDir;
  late String oceanPath;
  final messages = <String>[];
  final ggLog = messages.add;
  late MockGitHandler gitHandler;
  late MockFetch fetch;
  late MockCheckout checkout;
  late MockShowFile showFile;
  late MockRemoteBranches remoteBranches;
  late MockRemoteBranchExists remoteBranchExists;
  late MockProcessRunner proc;
  final copyCalls = <String>[];
  final fetchedUrls = <String>[];

  String ticketJsonStr({
    String issueId = 'feat_x',
    String desc = 'd',
    List<Map<String, String>> repos = const [
      {'name': 'repo_a', 'url': 'u_a'},
    ],
  }) => jsonEncode(<String, Object?>{
    'issue_id': issueId,
    'description': desc,
    'repositories': repos,
  });

  void stubShowFile(String? content) {
    when(
      () => showFile.get(
        directory: any(named: 'directory'),
        ggLog: any(named: 'ggLog'),
        ref: any(named: 'ref'),
        filePath: any(named: 'filePath'),
      ),
    ).thenAnswer((_) async => content);
  }

  Directory makeMasterRepo(String name) {
    final d = Directory(path.join(oceanPath, name))
      ..createSync(recursive: true);
    Directory(path.join(d.path, '.git')).createSync();
    File(path.join(d.path, 'pubspec.yaml')).writeAsStringSync('name: x\n');
    return d;
  }

  Future<void> fakeCopyDir(Directory src, Directory dest) async {
    copyCalls.add(dest.path);
    dest.createSync(recursive: true);
    File(path.join(dest.path, 'pubspec.yaml')).writeAsStringSync('name: x\n');
  }

  setUp(() {
    messages.clear();
    copyCalls.clear();
    fetchedUrls.clear();
    tempDir = Directory.systemTemp.createTempSync('do_checkout_test');
    oceanPath = path.join(tempDir.path, '.ocean');
    Directory(oceanPath).createSync(recursive: true);

    gitHandler = MockGitHandler();
    fetch = MockFetch();
    checkout = MockCheckout();
    showFile = MockShowFile();
    remoteBranches = MockRemoteBranches();
    remoteBranchExists = MockRemoteBranchExists();
    proc = MockProcessRunner();

    when(
      () => fetch.get(
        directory: any(named: 'directory'),
        ggLog: any(named: 'ggLog'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => checkout.get(
        directory: any(named: 'directory'),
        ggLog: any(named: 'ggLog'),
        branch: any(named: 'branch'),
      ),
    ).thenAnswer((_) async {});
    stubShowFile(ticketJsonStr());
    when(
      () => remoteBranches.get(
        directory: any(named: 'directory'),
        ggLog: any(named: 'ggLog'),
      ),
    ).thenAnswer((_) async => ['main', 'master', 'feat_x']);
    when(
      () => remoteBranchExists.get(
        directory: any(named: 'directory'),
        ggLog: any(named: 'ggLog'),
        branch: any(named: 'branch'),
      ),
    ).thenAnswer((_) async => true);
    when(() => gitHandler.cloneRepo(any(), any())).thenAnswer((_) async {});
    when(
      () => proc.call(
        any(),
        any(),
        workingDirectory: any(named: 'workingDirectory'),
        runInShell: any(named: 'runInShell'),
      ),
    ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  DoCheckoutCommand build({
    String? executionPath,
    BranchSelector? selectBranch,
    CopyDirectory? copyDir,
    TicketJsonFetcher? fetchTicketJson,
  }) => DoCheckoutCommand(
    fetchTicketJson:
        fetchTicketJson ??
        (url) async {
          fetchedUrls.add(url.toString());
          return ticketJsonStr();
        },
    ggLog: ggLog,
    gitHandler: gitHandler,
    fetch: fetch,
    checkout: checkout,
    showFile: showFile,
    remoteBranches: remoteBranches,
    remoteBranchExists: remoteBranchExists,
    oceanWorkspacePath: oceanPath,
    executionPath: executionPath ?? tempDir.path,
    processRunner: proc.call,
    selectBranch: selectBranch ?? (b) async => b.first,
    copyDir: copyDir ?? fakeCopyDir,
  );

  Future<void> runCmd(DoCheckoutCommand cmd, List<String> args) async {
    final runner = CommandRunner<dynamic>('gg', 'gg')..addCommand(cmd);
    await runner.run(['ticket', ...args]);
  }

  Directory ticketDirOf(String name) =>
      Directory(path.join(tempDir.path, 'tickets', name));

  bool logged(String fragment) => messages.any((m) => m.contains(fragment));

  group('DoCheckoutCommand', () {
    test('has the expected name and description', () {
      final cmd = build();
      expect(cmd.name, 'ticket');
      expect(cmd.description, contains('Reproduce a ticket'));
    });

    test('throws UsageException when no name is given', () async {
      await expectLater(runCmd(build(), []), throwsA(isA<UsageException>()));
    });

    group('ticket.json given as a file path', () {
      late Directory sourceDir;

      setUp(() {
        sourceDir = Directory(path.join(tempDir.path, 'shared'))
          ..createSync(recursive: true);
      });

      File writeSource(String content, {String name = 'ticket.json'}) =>
          File(path.join(sourceDir.path, name))..writeAsStringSync(content);

      test('reproduces the ticket from the file', () async {
        makeMasterRepo('repo_a');
        final file = writeSource(ticketJsonStr());

        await runCmd(build(), [file.path]);

        final tdir = ticketDirOf('feat_x');
        expect(
          File(path.join(tdir.path, ticketJsonFileName)).existsSync(),
          isTrue,
        );
        expect(File(path.join(tdir.path, 'ticket.json')).existsSync(), isTrue);
        expect(logged('Checked out ticket feat_x'), isTrue);
      });

      test('accepts a file that is not called ticket.json', () async {
        makeMasterRepo('repo_a');
        final file = writeSource(ticketJsonStr(), name: 'shared_ticket.json');

        await runCmd(build(), [file.path]);

        expect(ticketDirOf('feat_x').existsSync(), isTrue);
      });

      test('accepts a ticket folder and reads its ticket.json', () async {
        makeMasterRepo('repo_a');
        writeSource(ticketJsonStr());

        await runCmd(build(), [sourceDir.path]);

        expect(ticketDirOf('feat_x').existsSync(), isTrue);
      });

      test('never contacts the network for a file path', () async {
        makeMasterRepo('repo_a');
        await runCmd(build(), [writeSource(ticketJsonStr()).path]);
        expect(fetchedUrls, isEmpty);
      });

      test('throws when the file holds no valid ticket.json', () async {
        final file = writeSource('{not json');
        await expectLater(
          runCmd(build(), [file.path]),
          throwsA(
            predicate(
              (e) =>
                  rmControls(e.toString()).contains('Invalid ticket.json at "'),
            ),
          ),
        );
      });

      test('throws when the folder has no ticket.json', () async {
        await expectLater(
          runCmd(build(), [sourceDir.path]),
          throwsA(
            predicate(
              (e) =>
                  rmControls(e.toString()).contains('contains no ticket.json'),
            ),
          ),
        );
      });

      test('leaves a plain name to the legacy branch modes', () async {
        final repoA = makeMasterRepo('repo_a');
        await runCmd(build(executionPath: repoA.path), ['feat_x']);
        expect(ticketDirOf('feat_x').existsSync(), isTrue);
      });
    });

    group('ticket.json given as a URL', () {
      test('downloads the ticket.json and reproduces the ticket', () async {
        makeMasterRepo('repo_a');

        await runCmd(build(), ['https://example.com/t/ticket.json']);

        expect(fetchedUrls, ['https://example.com/t/ticket.json']);
        expect(ticketDirOf('feat_x').existsSync(), isTrue);
        expect(logged('Downloading ticket.json from'), isTrue);
      });

      test('accepts a plain http URL', () async {
        makeMasterRepo('repo_a');
        await runCmd(build(), ['http://example.com/ticket.json']);
        expect(fetchedUrls, ['http://example.com/ticket.json']);
      });

      test('propagates a download failure', () async {
        await expectLater(
          runCmd(
            build(fetchTicketJson: (_) async => throw Exception('HTTP 404')),
            ['https://example.com/ticket.json'],
          ),
          throwsA(
            predicate((e) => rmControls(e.toString()).contains('HTTP 404')),
          ),
        );
      });

      test('throws when the download is no valid ticket.json', () async {
        await expectLater(
          runCmd(build(fetchTicketJson: (_) async => '<html>404</html>'), [
            'https://example.com/ticket.json',
          ]),
          throwsA(
            predicate(
              (e) =>
                  rmControls(e.toString()).contains('Invalid ticket.json at'),
            ),
          ),
        );
      });

      test('throws when the ticket.json needs a newer gg', () async {
        await expectLater(
          runCmd(
            build(
              fetchTicketJson: (_) async => jsonEncode(<String, Object?>{
                'issue_id': 'feat_x',
                'description': 'd',
                'gg_version': '9999.0.0',
                'repositories': <Object?>[],
              }),
            ),
            ['https://example.com/ticket.json'],
          ),
          throwsA(
            predicate((e) => rmControls(e.toString()).contains('9999.0.0')),
          ),
        );
      });
    });

    group('mode 1 (inside an ocean repo)', () {
      test('reproduces the ticket from the current repo branch', () async {
        final repoA = makeMasterRepo('repo_a');
        await runCmd(build(executionPath: repoA.path), ['feat_x']);

        final tdir = ticketDirOf('feat_x');
        expect(tdir.existsSync(), isTrue);
        expect(
          File(path.join(tdir.path, ticketJsonFileName)).existsSync(),
          isTrue,
        );
        expect(
          File(path.join(tdir.path, 'feat_x.code-workspace')).existsSync(),
          isTrue,
        );
        expect(copyCalls.any((p) => p.endsWith('repo_a')), isTrue);
        verify(
          () => checkout.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            branch: 'feat_x',
          ),
        ).called(1);
        expect(logged('Executed dart pub get in repo_a'), isTrue);
        expect(logged('Checked out ticket feat_x'), isTrue);
      });

      test('an exec at ocean root is not treated as mode 1', () async {
        makeMasterRepo('repo_a');
        when(
          () => remoteBranchExists.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            branch: any(named: 'branch'),
          ),
        ).thenAnswer((_) async => false);
        await expectLater(
          runCmd(build(executionPath: oceanPath), ['nope']),
          throwsA(isA<Exception>()),
        );
      });

      test('an exec in a non-existent ocean subdir is not mode 1', () async {
        await expectLater(
          runCmd(build(executionPath: path.join(oceanPath, 'ghost')), ['nope']),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('mode 2 (known repo, interactive)', () {
      test('lists branches and reproduces the selected one', () async {
        makeMasterRepo('repo_a');
        await runCmd(build(), ['repo_a']);

        verify(
          () => remoteBranches.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).called(1);
        verify(
          () => checkout.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            branch: 'feat_x',
          ),
        ).called(1);
        expect(ticketDirOf('feat_x').existsSync(), isTrue);
      });

      test('logs when there are no ticket branches', () async {
        makeMasterRepo('repo_a');
        when(
          () => remoteBranches.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async => ['main', 'master']);
        await runCmd(build(), ['repo_a']);

        expect(logged('No ticket branches found'), isTrue);
        verifyNever(
          () => checkout.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            branch: any(named: 'branch'),
          ),
        );
      });

      test('returns when the selection is cancelled (null)', () async {
        makeMasterRepo('repo_a');
        await runCmd(build(selectBranch: (b) async => null), ['repo_a']);
        verifyNever(
          () => showFile.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            ref: any(named: 'ref'),
            filePath: any(named: 'filePath'),
          ),
        );
      });

      test('returns when the selection is empty', () async {
        makeMasterRepo('repo_a');
        await runCmd(build(selectBranch: (b) async => ''), ['repo_a']);
        verifyNever(
          () => showFile.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            ref: any(named: 'ref'),
            filePath: any(named: 'filePath'),
          ),
        );
      });
    });

    group('mode 3 (search by ticket name)', () {
      test('finds the branch across ocean repos and reproduces', () async {
        makeMasterRepo('repo_a');
        await runCmd(build(), ['feat_x']);

        verify(
          () => remoteBranchExists.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            branch: 'feat_x',
          ),
        ).called(1);
        expect(ticketDirOf('feat_x').existsSync(), isTrue);
      });

      test('throws when no repo has the branch', () async {
        makeMasterRepo('repo_a');
        when(
          () => remoteBranchExists.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            branch: any(named: 'branch'),
          ),
        ).thenAnswer((_) async => false);
        await expectLater(
          runCmd(build(), ['feat_x']),
          throwsA(
            predicate(
              (e) => rmControls(
                e.toString(),
              ).contains('is neither a ticket.json path'),
            ),
          ),
        );
      });

      test('skips a repo whose fetch fails, then throws not-found', () async {
        makeMasterRepo('repo_a');
        when(
          () => fetch.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenThrow(Exception('boom'));
        await expectLater(
          runCmd(build(), ['feat_x']),
          throwsA(isA<Exception>()),
        );
        expect(logged('Failed to fetch repo_a'), isTrue);
      });

      test('throws cleanly when the ocean is missing', () async {
        Directory(oceanPath).deleteSync(recursive: true);
        await expectLater(runCmd(build(), ['nope']), throwsA(isA<Exception>()));
      });
    });

    group('marker handling', () {
      test('throws when the branch has no ticket marker', () async {
        final repoA = makeMasterRepo('repo_a');
        stubShowFile(null);
        await expectLater(
          runCmd(build(executionPath: repoA.path), ['feat_x']),
          throwsA(
            predicate(
              (e) => rmControls(
                e.toString(),
              ).contains('Could not read a ticket marker'),
            ),
          ),
        );
      });

      test('warns that the legacy marker is deprecated', () async {
        final repoA = makeMasterRepo('repo_a');
        await runCmd(build(executionPath: repoA.path), ['feat_x']);
        expect(logged('legacy ticket marker'), isTrue);
      });

      test('falls back to the unhidden .gg/ticket.json', () async {
        final repoA = makeMasterRepo('repo_a');
        when(
          () => showFile.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            ref: any(named: 'ref'),
            filePath: any(named: 'filePath'),
          ),
        ).thenAnswer(
          (i) async => i.namedArguments[#filePath] == '.gg/ticket.json'
              ? ticketJsonStr()
              : null,
        );

        await runCmd(build(executionPath: repoA.path), ['feat_x']);
        expect(ticketDirOf('feat_x').existsSync(), isTrue);
      });

      test('throws on an invalid ticket marker', () async {
        final repoA = makeMasterRepo('repo_a');
        stubShowFile('[1, 2]');
        await expectLater(
          runCmd(build(executionPath: repoA.path), ['feat_x']),
          throwsA(
            predicate(
              (e) => rmControls(e.toString()).contains('Invalid ticket.json'),
            ),
          ),
        );
      });

      test('throws when the marker has no issue_id', () async {
        final repoA = makeMasterRepo('repo_a');
        stubShowFile(ticketJsonStr(issueId: ''));
        await expectLater(
          runCmd(build(executionPath: repoA.path), ['feat_x']),
          throwsA(
            predicate((e) => rmControls(e.toString()).contains('no issue_id')),
          ),
        );
      });
    });

    group('reproduce repositories', () {
      test('skips a ticket repo that cannot be obtained', () async {
        final repoA = makeMasterRepo('repo_a');
        stubShowFile(
          ticketJsonStr(
            repos: const [
              {'name': 'ghost', 'url': ''},
            ],
          ),
        );
        await runCmd(build(executionPath: repoA.path), ['feat_x']);
        expect(logged('Could not obtain repository ghost'), isTrue);
        expect(logged('1 repo(s) failed: ghost'), isTrue);
        // The workspace file does not list the skipped repo.
        final ws = File(
          path.join(ticketDirOf('feat_x').path, 'feat_x.code-workspace'),
        ).readAsStringSync();
        expect(ws.contains('ghost'), isFalse);
      });

      test('clones a missing ticket repo from its url', () async {
        final repoA = makeMasterRepo('repo_a');
        stubShowFile(
          ticketJsonStr(
            repos: const [
              {'name': 'new_repo', 'url': 'https://x/new_repo.git'},
            ],
          ),
        );
        await runCmd(build(executionPath: repoA.path), ['feat_x']);
        verify(
          () => gitHandler.cloneRepo(
            'https://x/new_repo.git',
            path.join(oceanPath, 'new_repo'),
          ),
        ).called(1);
      });

      test('logs and skips when cloning a missing repo fails', () async {
        final repoA = makeMasterRepo('repo_a');
        stubShowFile(
          ticketJsonStr(
            repos: const [
              {'name': 'new_repo', 'url': 'u'},
            ],
          ),
        );
        when(
          () => gitHandler.cloneRepo(any(), any()),
        ).thenThrow(Exception('clone failed'));
        await runCmd(build(executionPath: repoA.path), ['feat_x']);
        expect(logged('Failed to clone new_repo'), isTrue);
        expect(logged('Could not obtain repository new_repo'), isTrue);
      });

      test('does not re-copy a repo already present in the ticket', () async {
        final repoA = makeMasterRepo('repo_a');
        final dest = Directory(
          path.join(tempDir.path, 'tickets', 'feat_x', 'repo_a'),
        )..createSync(recursive: true);
        File(path.join(dest.path, 'pubspec.yaml')).writeAsStringSync('name: x');
        await runCmd(build(executionPath: repoA.path), ['feat_x']);
        expect(copyCalls.any((p) => p.endsWith('repo_a')), isFalse);
        verify(
          () => checkout.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            branch: 'feat_x',
          ),
        ).called(1);
      });

      test('logs and stops a repo when checkout fails', () async {
        final repoA = makeMasterRepo('repo_a');
        when(
          () => checkout.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            branch: any(named: 'branch'),
          ),
        ).thenThrow(Exception('co fail'));
        await runCmd(build(executionPath: repoA.path), ['feat_x']);
        expect(logged('Failed to checkout feat_x in repo_a'), isTrue);
        expect(logged('1 repo(s) failed: repo_a'), isTrue);
        verifyNever(
          () => proc.call(
            any(),
            any(),
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: any(named: 'runInShell'),
          ),
        );
      });
    });

    group('dependency install', () {
      test('logs a failed dependency install', () async {
        final repoA = makeMasterRepo('repo_a');
        when(
          () => proc.call(
            any(),
            any(),
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: any(named: 'runInShell'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 1, '', 'err'));
        await runCmd(build(executionPath: repoA.path), ['feat_x']);
        expect(logged('Failed to execute dart pub get in repo_a'), isTrue);
      });

      test('installs TypeScript deps for a package.json repo', () async {
        final repoA = makeMasterRepo('repo_a');
        Future<void> tsCopyDir(Directory src, Directory dest) async {
          copyCalls.add(dest.path);
          dest.createSync(recursive: true);
          File(path.join(dest.path, 'package.json')).writeAsStringSync('{}');
        }

        await runCmd(build(executionPath: repoA.path, copyDir: tsCopyDir), [
          'feat_x',
        ]);
        verify(
          () => proc.call(
            any(),
            ['install'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: any(named: 'runInShell'),
          ),
        ).called(1);
        expect(logged('install in repo_a'), isTrue);
      });

      test('skips install when the repo has neither manifest', () async {
        final repoA = makeMasterRepo('repo_a');
        Future<void> emptyCopyDir(Directory src, Directory dest) async {
          copyCalls.add(dest.path);
          dest.createSync(recursive: true);
        }

        await runCmd(build(executionPath: repoA.path, copyDir: emptyCopyDir), [
          'feat_x',
        ]);
        verifyNever(
          () => proc.call(
            any(),
            any(),
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: any(named: 'runInShell'),
          ),
        );
        expect(logged('Added repo_a on branch feat_x'), isTrue);
      });
    });

    group('organization folders', () {
      // Creates `<ocean>/<org>/<repo>` with a git remote of that org.
      Directory makeOrgRepo(String org, String repo) {
        final d = Directory(path.join(oceanPath, org, repo))
          ..createSync(recursive: true);
        final gitDir = Directory(path.join(d.path, '.git'))..createSync();
        File(path.join(gitDir.path, 'config')).writeAsStringSync(
          '[remote "origin"]\n\turl = https://github.com/$org/$repo.git\n',
        );
        File(path.join(d.path, 'pubspec.yaml')).writeAsStringSync('name: x\n');
        return d;
      }

      test('reproduces the ticket with its organization folders', () async {
        makeOrgRepo('ggsuite', 'repo_a');

        await runCmd(build(executionPath: tempDir.path), ['feat_x']);

        final ticketDir = Directory(
          path.join(tempDir.path, 'tickets', 'feat_x'),
        );
        expect(copyCalls, [path.join(ticketDir.path, 'ggsuite', 'repo_a')]);

        // The VS Code workspace addresses the repo through its org folder.
        final ws =
            jsonDecode(
                  File(
                    path.join(ticketDir.path, 'feat_x.code-workspace'),
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;
        expect(
          (ws['folders'] as List<dynamic>).cast<Map<String, dynamic>>().map(
            (f) => f['path'] as String,
          ),
          <String>['ggsuite/repo_a'],
        );
      });

      test('clones a missing repo into its organization folder', () async {
        stubShowFile(
          ticketJsonStr(
            repos: <Map<String, String>>[
              <String, String>{
                'name': 'repo_a',
                'url': 'https://github.com/ggsuite/repo_a.git',
              },
            ],
          ),
        );
        // A second repo makes the command find an ocean repo to read the
        // marker from without providing repo_a itself.
        final other = makeOrgRepo('ggsuite', 'repo_b');

        await runCmd(build(executionPath: other.path), ['feat_x']);

        verify(
          () => gitHandler.cloneRepo(
            'https://github.com/ggsuite/repo_a.git',
            path.join(oceanPath, 'ggsuite', 'repo_a'),
          ),
        ).called(1);
      });

      test('moves the repos of an old ocean into their org folders', () async {
        final flat = Directory(path.join(oceanPath, 'repo_a'))
          ..createSync(recursive: true);
        final gitDir = Directory(path.join(flat.path, '.git'))..createSync();
        File(path.join(gitDir.path, 'config')).writeAsStringSync(
          '[remote "origin"]\n\turl = https://github.com/ggsuite/repo_a.git\n',
        );
        File(
          path.join(flat.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: x\n');

        await runCmd(build(executionPath: tempDir.path), ['feat_x']);

        expect(
          Directory(path.join(oceanPath, 'ggsuite', 'repo_a')).existsSync(),
          isTrue,
        );
        expect(Directory(path.join(oceanPath, 'repo_a')).existsSync(), isFalse);
      });

      test('detects the ocean repo the command runs in', () async {
        // Executed inside `<ocean>/<org>/<repo>`, the argument is the ticket
        // name, so the marker is read from that repo instead of searching.
        final repoA = makeOrgRepo('ggsuite', 'repo_a');

        await runCmd(build(executionPath: path.join(repoA.path, 'lib')), [
          'feat_x',
        ]);

        verifyNever(
          () => remoteBranchExists.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            branch: any(named: 'branch'),
          ),
        );
        expect(logged('Checked out ticket feat_x'), isTrue);
      });
    });
  });
}
