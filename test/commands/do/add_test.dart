// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

@Timeout(Duration(minutes: 2))
library;

import 'package:gg_git/gg_git.dart';

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
// ignore: lines_longer_than_80_chars
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_localize_refs/gg_localize_refs.dart';
import 'package:gg_multi_core/gg_multi_core.dart';
import 'package:gg_multi_workspace/src/backend/add_repository_helper.dart'
    show SelectOrganization;
import 'package:gg_multi_workspace/src/backend/git_handler.dart';
import 'package:gg_multi_workspace/src/commands/do/add.dart';
import 'package:gg_one/gg_one.dart' as gg;
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:test/test.dart';

class MockGitCloner extends Mock implements GitHandler {}

class MockGitHubPlatform extends Mock implements GitHubPlatform {}

class MockLocalizeRefs extends Mock implements ChangeRefsToLocal {}

class MockBackupPublishTo extends Mock implements BackupPublishTo {}

/// Localizes the refs of every repo but the one named [failing].
class FailingChangeRefsToLocal extends ChangeRefsToLocal {
  /// Constructor.
  FailingChangeRefsToLocal({required super.ggLog, required this.failing});

  /// The folder name of the repo that fails.
  final String failing;

  @override
  Future<void> get({
    required Directory directory,
    required void Function(String) ggLog,
  }) async {
    if (path.basename(directory.path) == failing) {
      throw Exception('localize failed');
    }
    await super.get(directory: directory, ggLog: ggLog);
  }
}

class MockProcessRunner extends Mock {
  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    bool runInShell,
    Map<String, String>? environment,
  });
}

class MockGgSystemCommit extends Mock implements gg.GgSystemCommit {}

class MockSortedProcessingList extends Mock implements SortedProcessingList {}

class MockGraph extends Mock implements Graph {}

/// A [DefaultBranch] that answers [name] for every repository — `main` by
/// default, so the tests that build their ocean repos out of plain folders
/// (no git at all) still see the reset the command would run on a real one.
DefaultBranch fakeDefaultBranch([String name = 'main']) {
  final mock = MockDefaultBranch();
  when(
    () => mock.get(
      directory: any(named: 'directory'),
      ggLog: any(named: 'ggLog'),
    ),
  ).thenAnswer((_) async => name);
  return mock;
}

/// Creates [name] in [ticketDir] as a git checkout on the ticket's branch
/// with [pubspec] as its committed manifest.
Future<Directory> gitTicketRepo(
  Directory ticketDir,
  String name,
  String pubspec,
) async {
  final dir = Directory(path.join(ticketDir.path, name))..createSync();
  File(path.join(dir.path, 'pubspec.yaml')).writeAsStringSync(pubspec);
  for (final args in [
    ['init', '-q', '-b', 'main'],
    ['config', 'user.email', 'test@example.com'],
    ['config', 'user.name', 'Test'],
    ['add', '.'],
    ['commit', '-q', '-m', 'Initial commit'],
    ['checkout', '-q', '-b', path.basename(ticketDir.path)],
  ]) {
    final result = await Process.run('git', args, workingDirectory: dir.path);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  }
  return dir;
}

/// Runs git in [dir] and returns its trimmed output.
Future<String> gitOutput(Directory dir, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: dir.path);
  return '${result.stdout}'.trim();
}

void main() {
  group('AddCommand', () {
    late MockGitCloner mockGitCloner;
    late List<String> logMessages;
    late CommandRunner<void> runner;
    late Directory tempDir;
    late String oceanWorkspacePath;

    void ggLog(String message) {
      logMessages.add(rmControls(message));
    }

    void createRunner({
      String? executionPath,
      Future<void> Function(String repoPath)? localizeRefsFn,
      ProcessRunner? processRunner,
      gg.GgSystemCommit? systemCommit,
      SortedProcessingList? sortedProcessingList,
      ChangeRefsToLocal? localizeRefs,
      BackupPublishTo? backupPublishTo,
      Graph? graph,
      FetchRepoUrl? fetchRepoUrl,
      DefaultBranch? defaultBranch,
      GitRetry gitRetry = const GitRetry(),
      GitHubPlatform? gitHubPlatform,
      SelectOrganization? selectOrganization,
      PubDevPackageExists? pubDevPackageExists,
      GgRc? ggRc,
      ReposBetween? reposBetween,
    }) {
      final execPath = Directory.systemTemp.createTempSync('exec_path_').path;
      // No test may list a real organization: by default none offers a repo.
      final noRepos = MockGitHubPlatform();
      when(() => noRepos.fetchOrgRepos(any(), client: any(named: 'client')))
          .thenAnswer((_) async => const <Repository>[]);
      runner = CommandRunner<void>('test', 'Test for AddCommand');
      runner.addCommand(
        AddCommand(
          ggLog: ggLog,
          readSettings: ggRc == null ? null : ({required ggLog}) => ggRc,
          reposBetween: reposBetween,
          gitCloner: mockGitCloner,
          gitHubPlatform: gitHubPlatform ?? noRepos,
          selectOrganization: selectOrganization,
          // No test may ask pub.dev: by default every package exists there.
          pubDevPackageExists: pubDevPackageExists ?? (_) async => true,
          processRunner: processRunner,
          oceanWorkspacePath: oceanWorkspacePath,
          executionPath: executionPath ?? execPath,
          systemCommit: systemCommit,
          sortedProcessingList: sortedProcessingList,
          localizeRefs: localizeRefs,
          backupPublishTo: backupPublishTo,
          graph: graph,
          fetchRepoUrl: fetchRepoUrl,
          defaultBranch: defaultBranch ?? fakeDefaultBranch(),
          gitRetry: gitRetry,
        ),
      );
    }

    setUp(() {
      mockGitCloner = MockGitCloner();
      logMessages = [];
      registerFallbackValue(Directory(''));
      when(() => mockGitCloner.cloneRepo(any(), any()))
          .thenAnswer((_) async {});
      tempDir = Directory.systemTemp.createTempSync('add_test');
      oceanWorkspacePath = path.join(tempDir.path, ggMultiOceanFolder);
      Directory(oceanWorkspacePath).createSync(recursive: true);
      final mockDoCommit = MockGgSystemCommit();
      when(
        () => mockDoCommit.commit(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          paths: any(named: 'paths'),
          includeUntracked: any(named: 'includeUntracked'),
          ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
          userCommitMessage: any(named: 'userCommitMessage'),
          stateKey: any(named: 'stateKey'),
          keepForeignChanges: any(named: 'keepForeignChanges'),
        ),
      ).thenAnswer(
        (_) async => const gg.GgSystemCommitResult(
          userCommitCreated: false,
          systemCommitCreated: true,
          ggOwnedPaths: ['pubspec_overrides.yaml'],
          foreignPaths: [],
        ),
      );
      createRunner(systemCommit: mockDoCommit);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('should clone single repository when target is a repo name', () async {
      await runner.run(['add', 'myrepo']);
      // GitHub is cloned over ssh, the organization is still registered by
      // its https url.
      verify(
        () =>
            mockGitCloner.cloneRepo('git@github.com:myrepo/myrepo.git', any()),
      ).called(1);
      expect(
        logMessages,
        anyElement(contains('myrepo from git@github.com:myrepo/myrepo.git')),
      );

      final orgFile = File(path.join(oceanWorkspacePath, '.organizations'));
      expect(orgFile.existsSync(), isTrue);
      final orgMap = (jsonDecode(orgFile.readAsStringSync()) as List<dynamic>)
          .map((e) => Organization.fromMap(e as Map<String, dynamic>))
          .toList();
      expect(orgMap.first.url, 'https://github.com/myrepo/');
    });

    test('should clone single repository when target is in username/repo '
        'format', () async {
      await runner.run(['add', 'testuser/testrepo']);
      verify(
        () => mockGitCloner.cloneRepo(
          'git@github.com:testuser/testrepo.git',
          any(),
        ),
      ).called(1);
      expect(
        logMessages,
        anyElement(
          contains('testrepo from git@github.com:testuser/testrepo.git'),
        ),
      );
    });

    test('should clone single repository when '
        'target is a full repository URL with .git', () async {
      const repoUrl = 'https://gitlab.com/someuser/somerepo.git';
      await runner.run(['add', repoUrl]);
      verify(() => mockGitCloner.cloneRepo(repoUrl, any())).called(1);
      expect(logMessages, anyElement(contains('somerepo from $repoUrl')));
    });

    test('should clone single repository when '
        'target is a git SSH URL', () async {
      const repoUrl = 'git@github.com:ggsuite/gg_multi.git';
      await runner.run(['add', repoUrl]);
      verify(() => mockGitCloner.cloneRepo(repoUrl, any())).called(1);
      expect(logMessages, anyElement(contains('gg_multi from $repoUrl')));
    });

    test('should clone single repository when '
        'target is a URL without .git', () async {
      const urlWithoutGit = 'https://github.com/ggsuite/gg_multi';
      await runner.run(['add', urlWithoutGit]);
      verify(
        () => mockGitCloner.cloneRepo(
          'git@github.com:ggsuite/gg_multi.git',
          any(),
        ),
      ).called(1);
      expect(
        logMessages,
        anyElement(
          contains('gg_multi from git@github.com:ggsuite/gg_multi.git'),
        ),
      );
    });

    test('should clone repositories when '
        'target is an organization URL', () async {
      final repoList = [
        const Repository(
          name: 'repo1',
          httpsUrl: 'https://github.com/myorganization/repo1.git',
        ),
        const Repository(
          name: 'repo2',
          httpsUrl: 'https://github.com/myorganization/repo2.git',
        ),
      ];

      final mockGitHubPlatform = MockGitHubPlatform();
      when(
        () => mockGitHubPlatform.fetchOrgRepos(
          any(),
          client: any(named: 'client'),
        ),
      ).thenAnswer((_) async => repoList);

      final orgRunner = CommandRunner<void>('test', 'Test for AddCommand Org');
      final mockDoCommit = MockGgSystemCommit();
      when(
        () => mockDoCommit.commit(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          paths: any(named: 'paths'),
          includeUntracked: any(named: 'includeUntracked'),
          ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
          userCommitMessage: any(named: 'userCommitMessage'),
          stateKey: any(named: 'stateKey'),
          keepForeignChanges: any(named: 'keepForeignChanges'),
        ),
      ).thenAnswer(
        (_) async => const gg.GgSystemCommitResult(
          userCommitCreated: false,
          systemCommitCreated: true,
          ggOwnedPaths: ['pubspec_overrides.yaml'],
          foreignPaths: [],
        ),
      );
      orgRunner.addCommand(
        AddCommand(
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          gitHubPlatform: mockGitHubPlatform,
          defaultBranch: fakeDefaultBranch(),
          oceanWorkspacePath: oceanWorkspacePath,
          // Without an execution path the command would resolve the ticket
          // of the checkout the tests run in and modify it.
          executionPath: tempDir.path,
          systemCommit: mockDoCommit,
        ),
      );
      const orgUrl = 'https://github.com/myorganization';
      await orgRunner.run(['add', orgUrl]);
      // The https urls the platform reports are cloned over ssh.
      verify(
        () => mockGitCloner.cloneRepo(
          'git@github.com:myorganization/repo1.git',
          any(),
        ),
      ).called(1);
      verify(
        () => mockGitCloner.cloneRepo(
          'git@github.com:myorganization/repo2.git',
          any(),
        ),
      ).called(1);
      expect(
        logMessages,
        anyElement(
          contains('repo1 from git@github.com:myorganization/repo1.git'),
        ),
      );
      expect(
        logMessages,
        anyElement(
          contains('repo2 from git@github.com:myorganization/repo2.git'),
        ),
      );
    });

    test(
      'should throw UsageException when target parameter is missing',
      () async {
        expect(() => runner.run(['add']), throwsA(isA<UsageException>()));
      },
    );

    test(
      'should throw exception when invalid organization URL is provided',
      () async {
        final invalidRunner = CommandRunner<void>(
          'test',
          'Test for AddCommand Invalid Org',
        );
        final mockDoCommit = MockGgSystemCommit();
        when(
          () => mockDoCommit.commit(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            paths: any(named: 'paths'),
            includeUntracked: any(named: 'includeUntracked'),
            ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
            userCommitMessage: any(named: 'userCommitMessage'),
            stateKey: any(named: 'stateKey'),
            keepForeignChanges: any(named: 'keepForeignChanges'),
          ),
        ).thenAnswer(
          (_) async => const gg.GgSystemCommitResult(
            userCommitCreated: false,
            systemCommitCreated: true,
            ggOwnedPaths: ['pubspec_overrides.yaml'],
            foreignPaths: [],
          ),
        );
        invalidRunner.addCommand(
          AddCommand(
            ggLog: ggLog,
            gitCloner: mockGitCloner,
            defaultBranch: fakeDefaultBranch(),
            oceanWorkspacePath: oceanWorkspacePath,
            // Without an execution path the command would resolve the ticket of
            // the checkout the tests run in and modify it.
            executionPath: tempDir.path,
            systemCommit: mockDoCommit,
          ),
        );
        const invalidOrgUrl = 'https://github.com/';
        expect(
          () => invalidRunner.run(['add', invalidOrgUrl]),
          throwsA(isA<Exception>()),
        );
      },
    );

    // .........................................................................
    group('target patterns', () {
      Directory oceanRepo(String name) =>
          Directory(path.join(oceanWorkspacePath, name))
            ..createSync(recursive: true);

      test('expands a pattern to the ocean repos it matches', () async {
        oceanRepo('ds_alpha');
        oceanRepo('ds_beta');
        oceanRepo('other');

        await runner.run(['add', 'ds_.+']);

        expect(logMessages, contains('  » ds_.+ matches ds_alpha, ds_beta'));
        expect(logMessages.join('\n'), isNot(contains('other')));
      });

      test('anchors the pattern, so a name is not a substring match', () async {
        oceanRepo('gg');
        oceanRepo('gg_multi');

        await runner.run(['add', 'gg']);

        // Not expanded — »gg« is one repo, not every name containing it.
        expect(logMessages.join('\n'), isNot(contains('matches')));
        expect(logMessages.join('\n'), isNot(contains('gg_multi')));
      });

      test('passes a target matching nothing through untouched', () async {
        // The ocean does not hold it yet, so it must still be cloned by name.
        await runner.run(['add', 'git@github.com:ggsuite/gg_multi.git']);

        verify(() => mockGitCloner.cloneRepo(any(), any())).called(1);
      });
    });

    group('matchOceanRepoNames', () {
      const names = ['ds_alpha', 'ds_beta', 'gg', 'gg_multi'];

      test('returns the matching names, sorted', () {
        expect(matchOceanRepoNames('ds_.+', names), ['ds_alpha', 'ds_beta']);
      });

      test('anchors the pattern at both ends', () {
        expect(matchOceanRepoNames('gg', names), ['gg']);
        expect(matchOceanRepoNames('multi', names), isEmpty);
      });

      test('anchors an alternation as a whole', () {
        // '^gg|ds_beta\$' would mean "starts with gg, or ends with ds_beta".
        expect(matchOceanRepoNames('gg|ds_beta', names), ['ds_beta', 'gg']);
      });

      test('returns nothing for an invalid regular expression', () {
        expect(matchOceanRepoNames('gg_multi[', names), isEmpty);
      });

      test('returns nothing for a url', () {
        expect(
          matchOceanRepoNames('git@github.com:ggsuite/gg_multi.git', names),
          isEmpty,
        );
      });
    });

    test('should log already added when destination '
        'exists and --force not provided', () async {
      const repoName = 'gg_multi';
      final destination = path.join(oceanWorkspacePath, repoName);
      Directory(destination).createSync(recursive: true);
      File(path.join(destination, 'dummy.txt')).writeAsStringSync('data');

      await runner.run(['add', 'git@github.com:ggsuite/gg_multi.git']);

      verifyNever(() => mockGitCloner.cloneRepo(any(), any()));
      expect(logMessages, contains('✓ $repoName (already added).'));
    });

    test('should force clone repository when --force '
        'is provided even if destination exists', () async {
      const repoName = 'gg_multi';
      final destination = path.join(oceanWorkspacePath, repoName);
      Directory(destination).createSync(recursive: true);
      File(path.join(destination, 'dummy.txt')).writeAsStringSync('data');

      await runner.run([
        'add',
        'git@github.com:ggsuite/gg_multi.git',
        '--force',
      ]);

      verify(() => mockGitCloner.cloneRepo(any(), any())).called(1);
    });

    test('retries an ocean fetch the remote dropped', () async {
      const repoName = 'testRepoRetry';
      final repoDir = Directory(path.join(oceanWorkspacePath, repoName))
        ..createSync(recursive: true);
      File(path.join(repoDir.path, 'pubspec.yaml'))
          .writeAsStringSync('name: project_retry\nversion: 1.0.0\n');
      final ticketDir = Directory(
        path.join(tempDir.path, ggMultiLegacyTicketFolder, 'TICKET'),
      )..createSync(recursive: true);

      final mockDoCommit = MockGgSystemCommit();
      when(
        () => mockDoCommit.commit(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          paths: any(named: 'paths'),
          includeUntracked: any(named: 'includeUntracked'),
          ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
          userCommitMessage: any(named: 'userCommitMessage'),
          stateKey: any(named: 'stateKey'),
          keepForeignChanges: any(named: 'keepForeignChanges'),
        ),
      ).thenAnswer(
        (_) async => const gg.GgSystemCommitResult(
          userCommitCreated: false,
          systemCommitCreated: true,
          ggOwnedPaths: ['pubspec_overrides.yaml'],
          foreignPaths: [],
        ),
      );

      // The first »git fetch« loses the connection; every other command
      // succeeds and reports nothing.
      var fetches = 0;
      Future<ProcessResult> processRunner(
        String executable,
        List<String> arguments, {
        String? workingDirectory,
        Map<String, String>? environment,
        bool runInShell = false,
      }) async {
        final isFetch = arguments.length == 1 && arguments.first == 'fetch';
        if (isFetch && ++fetches == 1) {
          return ProcessResult(
            0,
            128,
            '',
            'Connection to github.com closed by remote host.',
          );
        }
        return ProcessResult(0, 0, '', '');
      }

      createRunner(
        executionPath: ticketDir.path,
        systemCommit: mockDoCommit,
        processRunner: processRunner,
        gitRetry: GitRetry.example,
      );

      await runner.run(['add', '--verbose', repoName]);

      expect(fetches, 2);
      expect(
        logMessages.join('\n'),
        contains('git fetch failed with a transient network error'),
      );
      expect(
        File(path.join(ticketDir.path, repoName, 'pubspec.yaml')).existsSync(),
        isTrue,
      );
    });

    test('copies a repo into the ticket and localizes it', () async {
      const repoName = 'testRepoCommit';
      final repoDir = Directory(path.join(oceanWorkspacePath, repoName))
        ..createSync(recursive: true);
      File(path.join(repoDir.path, 'target.txt')).writeAsStringSync('content');
      const pubspecContent = '''
name: project123
version: 1.0.0
dependencies:
  json_dart: ^3.5.2
dev_dependencies:
  json_serializer: ^1.4.2
''';
      final pubspecFile = File(path.join(repoDir.path, 'pubspec.yaml'));
      pubspecFile.writeAsStringSync(pubspecContent);

      final ticketDir = Directory(
        path.join(tempDir.path, ggMultiLegacyTicketFolder, 'TICKET'),
      )..createSync(recursive: true);

      final mockDoCommit = MockGgSystemCommit();
      when(
        () => mockDoCommit.commit(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          paths: any(named: 'paths'),
          includeUntracked: any(named: 'includeUntracked'),
          ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
          userCommitMessage: any(named: 'userCommitMessage'),
          stateKey: any(named: 'stateKey'),
          keepForeignChanges: any(named: 'keepForeignChanges'),
        ),
      ).thenAnswer(
        (_) async => const gg.GgSystemCommitResult(
          userCommitCreated: false,
          systemCommitCreated: true,
          ggOwnedPaths: ['pubspec_overrides.yaml'],
          foreignPaths: [],
        ),
      );

      final mockProc = MockProcessRunner();
      when(
        () => mockProc(
          'git',
          ['fetch'],
          workingDirectory: repoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'git',
          ['remote', 'set-head', 'origin', '--auto'],
          workingDirectory: repoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'git',
          ['reset', '--hard', 'origin/main'],
          workingDirectory: repoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'git',
          ['tag', '-l'],
          workingDirectory: repoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => mockProc(
          'git',
          ['fetch', '--tags'],
          workingDirectory: repoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'git',
          ['fetch', '--prune', '--tags'],
          workingDirectory: repoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'dart',
          ['pub', 'get'],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
      when(
        () => mockProc(
          'dart',
          ['pub', 'upgrade'],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));

      when(
        () => mockProc(
          'git',
          ['status', '--porcelain', '--untracked-files=no'],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      createRunner(
        executionPath: ticketDir.path,
        systemCommit: mockDoCommit,
        processRunner: mockProc.call,
      );

      await runner.run(['add', '--verbose', repoName]);

      final copiedFileInTicket = File(
        path.join(ticketDir.path, repoName, 'target.txt'),
      );
      expect(copiedFileInTicket.existsSync(), isTrue);

      // The copy of a plain ocean folder is no git checkout: there is
      // nothing gg could commit to (see »keeps the user's work …«).
      verifyNever(
        () => mockDoCommit.commit(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          paths: any(named: 'paths'),
          includeUntracked: any(named: 'includeUntracked'),
          ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
          userCommitMessage: any(named: 'userCommitMessage'),
          stateKey: any(named: 'stateKey'),
          keepForeignChanges: any(named: 'keepForeignChanges'),
        ),
      );

      expect(
        logMessages.any(
          (m) => m.contains('Localized the references of all repos in ticket'),
        ),
        isTrue,
      );

      // The ticket.json is written into the ticket folder ...
      final ticketJson = File(path.join(ticketDir.path, 'ticket.json'));
      expect(ticketJson.existsSync(), isTrue);
      final markerContent = ticketJson.readAsStringSync();
      expect(markerContent, contains('"issue_id": "TICKET"'));
      expect(markerContent, contains('"repositories"'));

      // ... and never into a repository, where git could pick it up.
      // (`.gg` itself holds other gg state, so only the marker is checked.)
      final repoGg = path.join(ticketDir.path, repoName, '.gg');
      expect(File(path.join(repoGg, 'ticket.json')).existsSync(), isFalse);
      expect(File(path.join(repoGg, '.ticket.json')).existsSync(), isFalse);
    });

    test(
      'removes stale publish progress from the ocean repo before the copy',
      () async {
        const repoName = 'staleProgressRepo';
        final repoDir = Directory(path.join(oceanWorkspacePath, repoName))
          ..createSync(recursive: true);
        File(path.join(repoDir.path, 'target.txt'))
            .writeAsStringSync('content');
        const pubspecContent = '''
name: project123
version: 1.0.0
dependencies:
  json_dart: ^3.5.2
dev_dependencies:
  json_serializer: ^1.4.2
''';
        final pubspecFile = File(path.join(repoDir.path, 'pubspec.yaml'));
        pubspecFile.writeAsStringSync(pubspecContent);

        // A leftover runtime file of an aborted publish: it is gitignored,
        // so none of the git operations preparing the ocean repo removes
        // it — carried into a ticket it would block the next publish there.
        final ggDir = Directory(path.join(repoDir.path, '.gg'))
          ..createSync(recursive: true);
        File(path.join(ggDir.path, 'gg-publish.json')).writeAsStringSync(
          '{"done_steps":["prepare_version","publish_registry"]}',
        );
        File(path.join(ggDir.path, '.gg.json')).writeAsStringSync('{}');

        final ticketDir = Directory(
          path.join(tempDir.path, ggMultiLegacyTicketFolder, 'TICKET'),
        )..createSync(recursive: true);

        final mockDoCommit = MockGgSystemCommit();
        when(
          () => mockDoCommit.commit(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            paths: any(named: 'paths'),
            includeUntracked: any(named: 'includeUntracked'),
            ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
            userCommitMessage: any(named: 'userCommitMessage'),
            stateKey: any(named: 'stateKey'),
            keepForeignChanges: any(named: 'keepForeignChanges'),
          ),
        ).thenAnswer(
          (_) async => const gg.GgSystemCommitResult(
            userCommitCreated: false,
            systemCommitCreated: true,
            ggOwnedPaths: ['pubspec_overrides.yaml'],
            foreignPaths: [],
          ),
        );

        final mockProc = MockProcessRunner();
        when(
          () => mockProc(
            'git',
            ['fetch'],
            workingDirectory: repoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProc(
            'git',
            ['remote', 'set-head', 'origin', '--auto'],
            workingDirectory: repoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProc(
            'git',
            ['reset', '--hard', 'origin/main'],
            workingDirectory: repoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProc(
            'git',
            ['tag', '-l'],
            workingDirectory: repoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
        when(
          () => mockProc(
            'git',
            ['fetch', '--tags'],
            workingDirectory: repoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProc(
            'git',
            ['fetch', '--prune', '--tags'],
            workingDirectory: repoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProc(
            'dart',
            ['pub', 'get'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
        when(
          () => mockProc(
            'dart',
            ['pub', 'upgrade'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));

        when(
          () => mockProc(
            'git',
            ['status', '--porcelain', '--untracked-files=no'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
        createRunner(
          executionPath: ticketDir.path,
          systemCommit: mockDoCommit,
          processRunner: mockProc.call,
        );

        await runner.run(['add', '--verbose', repoName]);

        // The stale file is gone from the ocean repo …
        expect(
          File(path.join(ggDir.path, 'gg-publish.json')).existsSync(),
          isFalse,
        );
        expect(
          logMessages.any((m) => m.contains('Removed stale publish progress')),
          isTrue,
        );

        // … and never reached the ticket copy. Its sibling .gg.json did.
        expect(
          File(path.join(ticketDir.path, repoName, '.gg', 'gg-publish.json'))
              .existsSync(),
          isFalse,
        );
        expect(
          File(path.join(ticketDir.path, repoName, '.gg', '.gg.json'))
              .existsSync(),
          isTrue,
        );
      },
    );

    test('transitive scan clones a GitDependency declared in an existing '
        'repo via the org-fallback URL', () async {
      // Covers the GitDependency branch of `_cloneMissingTransitiveDeps`.
      const existingRepoName = 'tx_existing';
      const gitDepName = 'tx_git_dep';
      final existingRepoDir = Directory(
        path.join(oceanWorkspacePath, existingRepoName),
      )..createSync(recursive: true);
      File(path.join(existingRepoDir.path, 'pubspec.yaml')).writeAsStringSync(
        'name: $existingRepoName\n'
        'version: 1.0.0\n'
        'dependencies:\n'
        '  $gitDepName:\n'
        '    git:\n'
        '      url: https://github.com/some_org/$gitDepName.git\n',
      );

      final ticketDir = Directory(
        path.join(tempDir.path, ggMultiLegacyTicketFolder, 'TX_TICKET'),
      )..createSync(recursive: true);

      final mockProc = MockProcessRunner();
      when(
        () => mockProc(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

      final mockDoCommit = MockGgSystemCommit();
      when(
        () => mockDoCommit.commit(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          paths: any(named: 'paths'),
          includeUntracked: any(named: 'includeUntracked'),
          ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
          userCommitMessage: any(named: 'userCommitMessage'),
          stateKey: any(named: 'stateKey'),
          keepForeignChanges: any(named: 'keepForeignChanges'),
        ),
      ).thenAnswer(
        (_) async => const gg.GgSystemCommitResult(
          userCommitCreated: false,
          systemCommitCreated: true,
          ggOwnedPaths: ['pubspec_overrides.yaml'],
          foreignPaths: [],
        ),
      );

      when(
        () => mockProc(
          'git',
          ['status', '--porcelain', '--untracked-files=no'],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      createRunner(
        executionPath: ticketDir.path,
        processRunner: mockProc.call,
        systemCommit: mockDoCommit,
      );

      await runner.run(['add', existingRepoName]);

      // Org fallback: `github.com/<dep>/<dep>`, cloned over ssh.
      verify(
        () => mockGitCloner.cloneRepo(
          'git@github.com:$gitDepName/$gitDepName.git',
          any(),
        ),
      ).called(1);
    });

    test('transitive scan swallows a failing hosted-dep lookup and records '
        'a null cache entry', () async {
      // Covers the catch path in `_cloneMissingTransitiveDeps`.
      const existingRepoName = 'tx_existing_hosted';
      const hostedDepName = 'tx_hosted_dep';
      final existingRepoDir = Directory(
        path.join(oceanWorkspacePath, existingRepoName),
      )..createSync(recursive: true);
      File(path.join(existingRepoDir.path, 'pubspec.yaml')).writeAsStringSync(
        'name: $existingRepoName\n'
        'version: 1.0.0\n'
        'dependencies:\n'
        '  $hostedDepName: ^1.0.0\n',
      );

      final ticketDir = Directory(
        path.join(tempDir.path, ggMultiLegacyTicketFolder, 'TX_HOSTED_TICKET'),
      )..createSync(recursive: true);

      final mockProc = MockProcessRunner();
      when(
        () => mockProc(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

      final mockDoCommit = MockGgSystemCommit();
      when(
        () => mockDoCommit.commit(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          paths: any(named: 'paths'),
          includeUntracked: any(named: 'includeUntracked'),
          ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
          userCommitMessage: any(named: 'userCommitMessage'),
          stateKey: any(named: 'stateKey'),
          keepForeignChanges: any(named: 'keepForeignChanges'),
        ),
      ).thenAnswer(
        (_) async => const gg.GgSystemCommitResult(
          userCommitCreated: false,
          systemCommitCreated: true,
          ggOwnedPaths: ['pubspec_overrides.yaml'],
          foreignPaths: [],
        ),
      );

      var fetchCalls = 0;
      when(
        () => mockProc(
          'git',
          ['status', '--porcelain', '--untracked-files=no'],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      createRunner(
        executionPath: ticketDir.path,
        processRunner: mockProc.call,
        systemCommit: mockDoCommit,
        fetchRepoUrl: (pkg) async {
          fetchCalls++;
          throw Exception('boom: $pkg not reachable');
        },
      );

      await runner.run(['add', existingRepoName]);

      // Fetcher called; exception swallowed; cloner sees no phantom URL.
      expect(fetchCalls, greaterThanOrEqualTo(1));
      verifyNever(
        () =>
            mockGitCloner.cloneRepo(any(that: contains(hostedDepName)), any()),
      );
    });

    test('transitive scan accepts a hosted dep whose pub.dev repo URL '
        'belongs to a known org and queues it for cloning', () async {
      // Covers the inKnownOrg success branch of _cloneMissingTransitiveDeps.
      const existingRepoName = 'tx_existing_known';
      const hostedDepName = 'tx_known_org_dep';
      const orgUrl = 'https://github.com/myorg/';
      final existingRepoDir = Directory(
        path.join(oceanWorkspacePath, existingRepoName),
      )..createSync(recursive: true);
      File(path.join(existingRepoDir.path, 'pubspec.yaml')).writeAsStringSync(
        'name: $existingRepoName\n'
        'version: 1.0.0\n'
        'dependencies:\n'
        '  $hostedDepName: ^1.0.0\n',
      );
      File(path.join(oceanWorkspacePath, '.organizations')).writeAsStringSync(
        jsonEncode(<Map<String, dynamic>>[
          Organization(name: 'myorg', url: orgUrl).toMap(),
        ]),
      );

      final ticketDir = Directory(
        path.join(tempDir.path, ggMultiLegacyTicketFolder, 'TX_KNOWN_TICKET'),
      )..createSync(recursive: true);

      final mockProc = MockProcessRunner();
      when(
        () => mockProc(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

      final mockDoCommit = MockGgSystemCommit();
      when(
        () => mockDoCommit.commit(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          paths: any(named: 'paths'),
          includeUntracked: any(named: 'includeUntracked'),
          ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
          userCommitMessage: any(named: 'userCommitMessage'),
          stateKey: any(named: 'stateKey'),
          keepForeignChanges: any(named: 'keepForeignChanges'),
        ),
      ).thenAnswer(
        (_) async => const gg.GgSystemCommitResult(
          userCommitCreated: false,
          systemCommitCreated: true,
          ggOwnedPaths: ['pubspec_overrides.yaml'],
          foreignPaths: [],
        ),
      );

      // pub.dev names the https url, the repo is cloned over ssh.
      const repoUrl = '${orgUrl}tx_known_org_dep.git';
      const cloneUrl = 'git@github.com:myorg/tx_known_org_dep.git';
      when(
        () => mockProc(
          'git',
          ['status', '--porcelain', '--untracked-files=no'],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      createRunner(
        executionPath: ticketDir.path,
        processRunner: mockProc.call,
        systemCommit: mockDoCommit,
        fetchRepoUrl: (pkg) async => repoUrl,
      );

      await runner.run(['add', existingRepoName]);

      verify(() => mockGitCloner.cloneRepo(cloneUrl, any())).called(1);
    });

    test('transitive scan skips a hosted dep whose pub.dev repo URL '
        'belongs to an unknown org', () async {
      // Covers the inKnownOrg = false branch of _cloneMissingTransitiveDeps.
      const existingRepoName = 'tx_existing_unknown';
      const hostedDepName = 'tx_unknown_org_dep';
      final existingRepoDir = Directory(
        path.join(oceanWorkspacePath, existingRepoName),
      )..createSync(recursive: true);
      File(path.join(existingRepoDir.path, 'pubspec.yaml')).writeAsStringSync(
        'name: $existingRepoName\n'
        'version: 1.0.0\n'
        'dependencies:\n'
        '  $hostedDepName: ^1.0.0\n',
      );
      File(path.join(oceanWorkspacePath, '.organizations')).writeAsStringSync(
        jsonEncode(<Map<String, dynamic>>[
          Organization(name: 'myorg', url: 'https://github.com/myorg/').toMap(),
        ]),
      );

      final ticketDir = Directory(
        path.join(tempDir.path, ggMultiLegacyTicketFolder, 'TX_UNKNOWN_TICKET'),
      )..createSync(recursive: true);

      final mockProc = MockProcessRunner();
      when(
        () => mockProc(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

      final mockDoCommit = MockGgSystemCommit();
      when(
        () => mockDoCommit.commit(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          paths: any(named: 'paths'),
          includeUntracked: any(named: 'includeUntracked'),
          ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
          userCommitMessage: any(named: 'userCommitMessage'),
          stateKey: any(named: 'stateKey'),
          keepForeignChanges: any(named: 'keepForeignChanges'),
        ),
      ).thenAnswer(
        (_) async => const gg.GgSystemCommitResult(
          userCommitCreated: false,
          systemCommitCreated: true,
          ggOwnedPaths: ['pubspec_overrides.yaml'],
          foreignPaths: [],
        ),
      );

      when(
        () => mockProc(
          'git',
          ['status', '--porcelain', '--untracked-files=no'],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      createRunner(
        executionPath: ticketDir.path,
        processRunner: mockProc.call,
        systemCommit: mockDoCommit,
        fetchRepoUrl: (pkg) async => 'https://github.com/dart-lang/$pkg.git',
      );

      await runner.run(['add', existingRepoName]);

      verifyNever(
        () =>
            mockGitCloner.cloneRepo(any(that: contains(hostedDepName)), any()),
      );
    });

    group('clones the organization repos the ocean lacks', () {
      late MockProcessRunner mockProc;
      late Directory ticketDir;

      /// An ocean repo [name] depending on [deps], hosted.
      void oceanDartRepo(String name, List<String> deps) {
        final dir = Directory(path.join(oceanWorkspacePath, 'myorg', name))
          ..createSync(recursive: true);
        File(path.join(dir.path, 'pubspec.yaml')).writeAsStringSync(
          'name: $name\n'
          'version: 1.0.0\n'
          'dependencies:\n'
          '${deps.map((d) => '  $d: ^1.0.0\n').join()}',
        );
      }

      /// A platform listing [repos] for every organization.
      MockGitHubPlatform offering(List<String> repos) {
        final platform = MockGitHubPlatform();
        when(() => platform.fetchOrgRepos(any(), client: any(named: 'client')))
            .thenAnswer(
              (_) async => [
                for (final name in repos)
                  Repository(
                    name: name,
                    httpsUrl: 'https://github.com/myorg/$name',
                    sshUrl: 'git@github.com:myorg/$name.git',
                  ),
              ],
            );
        return platform;
      }

      setUp(() {
        OrganizationUtils.clearCache();
        File(path.join(oceanWorkspacePath, '.organizations')).writeAsStringSync(
          jsonEncode(<Map<String, dynamic>>[
            Organization(
              name: 'myorg',
              url: 'https://github.com/myorg/',
            ).toMap(),
          ]),
        );
        ticketDir = Directory(path.join(tempDir.path, 'ORG_TICKET'))
          ..createSync(recursive: true);
        File(path.join(ticketDir.path, 'ticket.json')).writeAsStringSync('{}');
        mockProc = MockProcessRunner();
        when(
          () => mockProc(
            any(),
            any(),
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: any(named: 'runInShell'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      });

      tearDown(OrganizationUtils.clearCache);

      test('that no registry attributes to the organization', () async {
        // pub.dev knows nothing of org_dep: it is not published yet.
        oceanDartRepo('requested', ['org_dep', 'path']);
        createRunner(
          executionPath: ticketDir.path,
          processRunner: mockProc.call,
          fetchRepoUrl: (_) async => null,
          gitHubPlatform: offering(['requested', 'org_dep']),
        );

        await runner.run(['add', 'requested', '--no-localize']);

        verify(
          () => mockGitCloner.cloneRepo(
            'git@github.com:myorg/org_dep.git',
            any(),
          ),
        ).called(1);
        verifyNever(
          () => mockGitCloner.cloneRepo(any(that: contains('path')), any()),
        );
      });

      test('that an ocean repo the ticket reaches depends on', () async {
        // ticket repo t -> ocean repo m -> x: the transitive scan above
        // only follows the requested repos, x is found anyway.
        oceanDartRepo('m', ['x']);
        oceanDartRepo('other', []);
        final t = Directory(path.join(ticketDir.path, 't'))..createSync();
        File(path.join(t.path, 'pubspec.yaml')).writeAsStringSync(
          'name: t\nversion: 1.0.0\ndependencies:\n  m: ^1.0.0\n',
        );
        createRunner(
          executionPath: ticketDir.path,
          processRunner: mockProc.call,
          fetchRepoUrl: (_) async => null,
          gitHubPlatform: offering(['m', 'other', 'x']),
          defaultBranch: fakeDefaultBranch(),
        );

        await runner.run(['add', 'other', '--no-localize', '--no-fetch']);

        verify(
          () => mockGitCloner.cloneRepo('git@github.com:myorg/x.git', any()),
        ).called(1);
      });

      test(
        'letting the user pick when several organizations offer it',
        () async {
          File(path.join(oceanWorkspacePath, '.organizations'))
              .writeAsStringSync(
                jsonEncode(<Map<String, dynamic>>[
                  for (final org in ['myorg', 'otherorg'])
                    Organization(
                      name: org,
                      url: 'https://github.com/$org/',
                    ).toMap(),
                ]),
              );
          OrganizationUtils.clearCache();
          oceanDartRepo('requested', ['org_dep']);
          final offered = <String>[];
          createRunner(
            executionPath: ticketDir.path,
            processRunner: mockProc.call,
            fetchRepoUrl: (_) async => null,
            gitHubPlatform: offering(['requested', 'org_dep']),
            selectOrganization: (repoName, owners) async {
              offered.addAll([repoName, ...owners.map((o) => o.name)]);
              return owners.last;
            },
          );

          await runner.run(['add', 'requested', '--no-localize']);

          expect(offered, ['org_dep', 'myorg', 'otherorg']);
          verify(
            () => mockGitCloner.cloneRepo(
              'git@github.com:otherorg/org_dep.git',
              any(),
            ),
          ).called(1);
        },
      );

      test('and scans what it cloned with the registry pass again', () async {
        // requested -> c (only the org list knows it) -> foo, published from
        // the repository bar: only the registry pass can find bar.
        oceanDartRepo('requested', ['c']);
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((invocation) async {
              final url = invocation.positionalArguments[0] as String;
              final destination = invocation.positionalArguments[1] as String;
              final deps = url.endsWith('/c.git') ? '  foo: ^1.0.0\n' : '';
              Directory(destination).createSync(recursive: true);
              File(path.join(destination, 'pubspec.yaml')).writeAsStringSync(
                'name: ${path.basename(destination)}\nversion: 1.0.0\n'
                'dependencies:\n$deps',
              );
            });
        createRunner(
          executionPath: ticketDir.path,
          processRunner: mockProc.call,
          fetchRepoUrl: (pkg) async =>
              pkg == 'foo' ? 'https://github.com/myorg/bar' : null,
          gitHubPlatform: offering(['requested', 'c', 'bar']),
        );

        await runner.run(['add', 'requested', '--no-localize', '--no-fetch']);

        verify(
          () => mockGitCloner.cloneRepo('git@github.com:myorg/c.git', any()),
        ).called(1);
        verify(
          () =>
              mockGitCloner.cloneRepo(any(that: contains('myorg/bar')), any()),
        ).called(1);
      });

      test('and reports a repo it cannot clone', () async {
        oceanDartRepo('requested', ['org_dep']);
        when(
          () => mockGitCloner.cloneRepo(
            'git@github.com:myorg/org_dep.git',
            any(),
          ),
        ).thenThrow(Exception('permission denied'));
        createRunner(
          executionPath: ticketDir.path,
          processRunner: mockProc.call,
          fetchRepoUrl: (_) async => null,
          gitHubPlatform: offering(['requested', 'org_dep']),
        );

        await runner.run(['add', 'requested', '--no-localize']);

        // Tried once — the fixpoint loop does not retry it forever.
        verify(
          () => mockGitCloner.cloneRepo(
            'git@github.com:myorg/org_dep.git',
            any(),
          ),
        ).called(1);
        final manifest = path.join(
          oceanWorkspacePath,
          'myorg',
          'requested',
          'pubspec.yaml',
        );
        expect(
          logMessages,
          contains(
            startsWith(
              'Failed to clone org_dep, which org_dep in $manifest needs:',
            ),
          ),
        );
        expect(
          logMessages,
          contains(contains('git ls-remote git@github.com:myorg/org_dep.git')),
        );
      });

      test('and reports only the next step of an ssh problem', () async {
        oceanDartRepo('requested', ['org_dep']);
        when(
          () => mockGitCloner.cloneRepo(
            'git@github.com:myorg/org_dep.git',
            any(),
          ),
        ).thenThrow(SshSetupException('SSH does not know github.com yet.'));
        createRunner(
          executionPath: ticketDir.path,
          processRunner: mockProc.call,
          fetchRepoUrl: (_) async => null,
          gitHubPlatform: offering(['requested', 'org_dep']),
        );

        await runner.run(['add', 'requested', '--no-localize']);

        expect(
          logMessages,
          contains(endsWith('needs: SSH does not know github.com yet.')),
        );
        expect(logMessages, isNot(contains(contains('Probably your SSH key'))));
      });

      test('and warns about organizations it cannot list', () async {
        oceanDartRepo('requested', ['org_dep']);
        final broken = MockGitHubPlatform();
        when(() => broken.fetchOrgRepos(any(), client: any(named: 'client')))
            .thenThrow(Exception('gh not authenticated'));
        createRunner(
          executionPath: ticketDir.path,
          processRunner: mockProc.call,
          fetchRepoUrl: (_) async => null,
          gitHubPlatform: broken,
        );

        await runner.run(['add', 'requested', '--no-localize']);

        // Once, after the last round, with the reason and what to try.
        expect(
          logMessages.where(
            (m) => m.startsWith(
              '\n⚠️ Could not list the repositories of myorg: '
              'gh not authenticated',
            ),
          ),
          hasLength(1),
        );
        expect(logMessages, contains(contains('gh auth status')));
      });

      test('and reports a dependency it cannot see', () async {
        // Neither on pub.dev nor in the list of myorg: probably private.
        oceanDartRepo('requested', ['hidden_dep']);
        createRunner(
          executionPath: ticketDir.path,
          processRunner: mockProc.call,
          fetchRepoUrl: (_) async => null,
          gitHubPlatform: offering(['requested']),
          pubDevPackageExists: (package) async => package != 'hidden_dep',
        );

        await runner.run(['add', 'requested', '--no-localize']);

        final manifest = path.join(
          oceanWorkspacePath,
          'myorg',
          'requested',
          'pubspec.yaml',
        );
        expect(
          logMessages,
          contains(
            '\n⚠️ hidden_dep (in $manifest) is not in the ocean: pub.dev '
            'does not know it, and no repository list of myorg names it.',
          ),
        );
        expect(
          logMessages,
          contains(contains('gh repo view myorg/hidden_dep')),
        );
      });
    });

    test('creates .code-workspace for ticket with one repo', () async {
      const repoName = 'workspaceRepo';
      final repoDir = Directory(path.join(oceanWorkspacePath, repoName))
        ..createSync(recursive: true);
      File(path.join(repoDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: $repoName
version: 1.0.0
''');

      final ticketDir = Directory(
        path.join(tempDir.path, ggMultiLegacyTicketFolder, 'TICKET_WS'),
      )..createSync(recursive: true);

      final mockProc = MockProcessRunner();
      when(
        () => mockProc(
          'git',
          ['fetch'],
          workingDirectory: repoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'git',
          ['remote', 'set-head', 'origin', '--auto'],
          workingDirectory: repoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'git',
          ['reset', '--hard', 'origin/main'],
          workingDirectory: repoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'git',
          ['tag', '-l'],
          workingDirectory: repoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => mockProc(
          'git',
          ['fetch', '--tags'],
          workingDirectory: repoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'git',
          ['fetch', '--prune', '--tags'],
          workingDirectory: repoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'dart',
          ['pub', 'get'],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
      when(
        () => mockProc(
          'dart',
          ['pub', 'upgrade'],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));

      final mockDoCommit = MockGgSystemCommit();
      when(
        () => mockDoCommit.commit(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          paths: any(named: 'paths'),
          includeUntracked: any(named: 'includeUntracked'),
          ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
          userCommitMessage: any(named: 'userCommitMessage'),
          stateKey: any(named: 'stateKey'),
          keepForeignChanges: any(named: 'keepForeignChanges'),
        ),
      ).thenAnswer(
        (_) async => const gg.GgSystemCommitResult(
          userCommitCreated: false,
          systemCommitCreated: true,
          ggOwnedPaths: ['pubspec_overrides.yaml'],
          foreignPaths: [],
        ),
      );

      when(
        () => mockProc(
          'git',
          ['status', '--porcelain', '--untracked-files=no'],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      createRunner(
        executionPath: ticketDir.path,
        processRunner: mockProc.call,
        systemCommit: mockDoCommit,
      );

      await runner.run(['add', repoName]);

      final wsFile = File(
        path.join(ticketDir.path, 'TICKET_WS.code-workspace'),
      );
      expect(wsFile.existsSync(), isTrue);
      final json =
          jsonDecode(wsFile.readAsStringSync()) as Map<String, dynamic>;
      final folders = (json['folders'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final paths = folders.map((f) => f['path'] as String).toSet();
      expect(paths, equals(<String>{repoName}));
    });

    test('throws when the ocean repo has uncommitted changes', () async {
      const repoName = 'dirtyRepo';
      final oceanRepoDir = Directory(path.join(oceanWorkspacePath, repoName))
        ..createSync(recursive: true);
      File(path.join(oceanRepoDir.path, 'file.txt')).writeAsStringSync('x');

      final ticketDir = Directory(
        path.join(tempDir.path, ggMultiLegacyTicketFolder, 'TICKET_DIRTY'),
      )..createSync(recursive: true);

      final mockProc = MockProcessRunner();
      when(
        () => mockProc(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => mockProc(
          'git',
          ['status', '--porcelain', '--untracked-files=no'],
          workingDirectory: oceanRepoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, ' M file.txt\n', ''));

      createRunner(executionPath: ticketDir.path, processRunner: mockProc.call);

      await expectLater(
        () async => runner.run(['add', '--verbose', repoName]),
        throwsA(
          isA<Exception>().having(
            (e) => rmControls(e.toString()),
            'message',
            contains('Repository $repoName in the ocean is not clean'),
          ),
        ),
      );

      expect(
        logMessages.any(
          (m) => m.contains(
            'The repository $repoName in the ocean has '
            'uncommitted changes:',
          ),
        ),
        isTrue,
      );
      expect(logMessages.any((m) => m.contains('M file.txt')), isTrue);

      // The repo was not reset and not copied.
      verifyNever(
        () => mockProc(
          'git',
          ['reset', '--hard', 'origin/main'],
          workingDirectory: oceanRepoDir.path,
          runInShell: true,
        ),
      );
      expect(
        Directory(path.join(ticketDir.path, repoName)).existsSync(),
        isFalse,
      );
    });

    test('logs when git status fails and continues', () async {
      const repoName = 'statusFailRepo';
      final oceanRepoDir = Directory(path.join(oceanWorkspacePath, repoName))
        ..createSync(recursive: true);
      File(path.join(oceanRepoDir.path, 'file.txt')).writeAsStringSync('x');

      final ticketDir = Directory(
        path.join(
          tempDir.path,
          ggMultiLegacyTicketFolder,
          'TICKET_STATUS_FAIL',
        ),
      )..createSync(recursive: true);

      final mockProc = MockProcessRunner();
      when(
        () => mockProc(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => mockProc(
          'git',
          ['status', '--porcelain', '--untracked-files=no'],
          workingDirectory: oceanRepoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 1, '', 'status error'));

      createRunner(executionPath: ticketDir.path, processRunner: mockProc.call);

      await runner.run(['add', '--verbose', repoName]);

      expect(
        logMessages.any(
          (m) => m.contains(
            'Failed to execute git status in $repoName in ocean: status error',
          ),
        ),
        isTrue,
      );
      expect(
        Directory(path.join(ticketDir.path, repoName)).existsSync(),
        isTrue,
      );
    });

    test('says once what to do when ssh fails for the git calls', () async {
      const repoName = 'sshFailRepo';
      // In the folder of its organization, where the remote url puts it.
      final oceanRepoDir = Directory(
        path.join(oceanWorkspacePath, 'org', repoName),
      )..createSync(recursive: true);
      File(path.join(oceanRepoDir.path, 'file.txt')).writeAsStringSync('x');
      Directory(path.join(oceanRepoDir.path, '.git')).createSync();
      File(path.join(oceanRepoDir.path, '.git', 'config')).writeAsStringSync(
        '[remote "origin"]\n\turl = git@github.com:org/$repoName.git\n',
      );

      final ticketDir = Directory(
        path.join(tempDir.path, ggMultiLegacyTicketFolder, 'TICKET_SSH_FAIL'),
      )..createSync(recursive: true);

      final mockProc = MockProcessRunner();
      when(
        () => mockProc(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      // Every network call of the ocean repo fails: ssh does not know the
      // host. The local ones work.
      for (final arguments in [
        ['fetch'],
        ['remote', 'set-head', 'origin', '--auto'],
        ['fetch', '--tags'],
      ]) {
        when(
          () => mockProc(
            'git',
            arguments,
            workingDirectory: oceanRepoDir.path,
            runInShell: true,
          ),
        ).thenAnswer(
          (_) async =>
              ProcessResult(0, 128, '', 'Host key verification failed.'),
        );
      }

      createRunner(executionPath: ticketDir.path, processRunner: mockProc.call);

      await runner.run(['add', '--verbose', repoName]);

      expect(
        logMessages.where((m) => m.startsWith('Failed to execute git fetch')),
        hasLength(2),
      );
      expect(
        logMessages.where(
          (m) => m.startsWith('SSH does not know github.com yet.'),
        ),
        hasLength(1),
      );
    });

    test('logs error when git reset fails but still copies repo', () async {
      const repoName = 'pullFailRepo';
      final oceanRepoDir = Directory(path.join(oceanWorkspacePath, repoName))
        ..createSync(recursive: true);
      File(path.join(oceanRepoDir.path, 'file.txt')).writeAsStringSync('x');

      final ticketDir = Directory(
        path.join(tempDir.path, ggMultiLegacyTicketFolder, 'TICKET_PULL_FAIL'),
      )..createSync(recursive: true);

      final mockProc = MockProcessRunner();
      final mockSorted = MockSortedProcessingList();
      final mockDoCommit = MockGgSystemCommit();
      final mockGraph = MockGraph();

      when(
        () => mockDoCommit.commit(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          paths: any(named: 'paths'),
          includeUntracked: any(named: 'includeUntracked'),
          ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
          userCommitMessage: any(named: 'userCommitMessage'),
          stateKey: any(named: 'stateKey'),
          keepForeignChanges: any(named: 'keepForeignChanges'),
        ),
      ).thenAnswer(
        (_) async => const gg.GgSystemCommitResult(
          userCommitCreated: false,
          systemCommitCreated: true,
          ggOwnedPaths: ['pubspec_overrides.yaml'],
          foreignPaths: [],
        ),
      );

      when(
        () => mockGraph.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          packageDirs: any(named: 'packageDirs'),
        ),
      ).thenAnswer((_) async => <String, Node>{});

      when(
        () => mockSorted.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async => <Node>[]);

      when(
        () => mockProc(
          'git',
          ['fetch'],
          workingDirectory: oceanRepoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'git',
          ['remote', 'set-head', 'origin', '--auto'],
          workingDirectory: oceanRepoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'git',
          ['reset', '--hard', 'origin/main'],
          workingDirectory: oceanRepoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(1, 1, '', 'reset error'));
      when(
        () => mockProc(
          'git',
          ['tag', '-l'],
          workingDirectory: oceanRepoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => mockProc(
          'git',
          ['fetch', '--tags'],
          workingDirectory: oceanRepoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'git',
          ['fetch', '--prune', '--tags'],
          workingDirectory: oceanRepoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'dart',
          ['pub', 'get'],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
      when(
        () => mockProc(
          'dart',
          ['pub', 'upgrade'],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));

      when(
        () => mockProc(
          'git',
          ['status', '--porcelain', '--untracked-files=no'],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      final localRunner = CommandRunner<void>('test', 'Add pull fail')
        ..addCommand(
          AddCommand(
            ggLog: ggLog,
            gitCloner: mockGitCloner,
            processRunner: mockProc.call,
            oceanWorkspacePath: oceanWorkspacePath,
            executionPath: ticketDir.path,
            systemCommit: mockDoCommit,
            sortedProcessingList: mockSorted,
            graph: mockGraph,
            defaultBranch: fakeDefaultBranch(),
          ),
        );

      await localRunner.run(['add', '--verbose', repoName]);

      final copied = Directory(path.join(ticketDir.path, repoName));
      expect(copied.existsSync(), isTrue);
      expect(
        logMessages.any(
          (m) => m.contains(
            'Failed to execute git reset --hard origin/main in '
            'pullFailRepo in ocean: reset error',
          ),
        ),
        isTrue,
      );
      verify(
        () => mockProc(
          'git',
          ['fetch'],
          workingDirectory: oceanRepoDir.path,
          runInShell: true,
        ),
      ).called(1);
      verify(
        () => mockProc(
          'git',
          ['remote', 'set-head', 'origin', '--auto'],
          workingDirectory: oceanRepoDir.path,
          runInShell: true,
        ),
      ).called(1);
      verify(
        () => mockProc(
          'git',
          ['reset', '--hard', 'origin/main'],
          workingDirectory: oceanRepoDir.path,
          runInShell: true,
        ),
      ).called(1);
      verify(
        () => mockProc(
          'git',
          ['tag', '-l'],
          workingDirectory: oceanRepoDir.path,
          runInShell: true,
        ),
      ).called(1);
      verify(
        () => mockProc(
          'git',
          ['fetch', '--tags'],
          workingDirectory: oceanRepoDir.path,
          runInShell: true,
        ),
      ).called(1);
      verify(
        () => mockProc(
          'git',
          ['fetch', '--prune', '--tags'],
          workingDirectory: oceanRepoDir.path,
          runInShell: true,
        ),
      ).called(1);
    });

    test('logs error when repo not found in ocean', () async {
      final ticketDir = Directory(
        path.join(tempDir.path, ggMultiLegacyTicketFolder, 'TICKET-MISSING'),
      )..createSync(recursive: true);
      createRunner(executionPath: ticketDir.path);
      await runner.run(['add', '--verbose', 'nonexistent']);
      expect(
        logMessages,
        contains('Repository nonexistent not found in ocean.'),
      );
    });

    test('logs already exists in ticket workspace if copied before', () async {
      const repoName = 'someGreyRepo';
      final repoDir = Directory(path.join(oceanWorkspacePath, repoName))
        ..createSync(recursive: true);
      File(path.join(repoDir.path, 'foo.txt')).writeAsStringSync('hi');

      final ticketDir = Directory(
        path.join(tempDir.path, ggMultiLegacyTicketFolder, 'ALREADY'),
      )..createSync(recursive: true);
      createRunner(executionPath: ticketDir.path);
      final destination = Directory(path.join(ticketDir.path, repoName));
      destination.createSync(recursive: true);
      File(path.join(destination.path, 'foo.txt')).writeAsStringSync('hi');

      await runner.run(['add', '--verbose', repoName]);

      expect(
        logMessages,
        contains('$repoName already exists in ticket workspace.'),
      );
    });

    test('does not set status if localization fails in ticket '
        'localization', () async {
      const repoName = 'failStatusRepo';
      final repoDir = Directory(path.join(oceanWorkspacePath, repoName))
        ..createSync(recursive: true);
      File(path.join(repoDir.path, 'dummy.txt')).writeAsStringSync('data');

      final ticketDir = Directory(
        path.join(tempDir.path, ggMultiLegacyTicketFolder, 'TICKET-FAIL'),
      )..createSync(recursive: true);
      final mockDoCommit = MockGgSystemCommit();
      when(
        () => mockDoCommit.commit(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          paths: any(named: 'paths'),
          includeUntracked: any(named: 'includeUntracked'),
          ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
          userCommitMessage: any(named: 'userCommitMessage'),
          stateKey: any(named: 'stateKey'),
          keepForeignChanges: any(named: 'keepForeignChanges'),
        ),
      ).thenAnswer(
        (_) async => const gg.GgSystemCommitResult(
          userCommitCreated: false,
          systemCommitCreated: true,
          ggOwnedPaths: ['pubspec_overrides.yaml'],
          foreignPaths: [],
        ),
      );

      createRunner(executionPath: ticketDir.path, systemCommit: mockDoCommit);

      await runner.run(['add', repoName]);

      verifyNever(
        () => mockDoCommit.commit(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          paths: any(named: 'paths'),
          includeUntracked: any(named: 'includeUntracked'),
          ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
          userCommitMessage: any(named: 'userCommitMessage'),
          stateKey: any(named: 'stateKey'),
          keepForeignChanges: any(named: 'keepForeignChanges'),
        ),
      );
    });

    group('dart pub get in _addRepoToTicket', () {
      late MockProcessRunner mockProcessRunner;
      late Directory ticketDir;
      late Directory repoDir;
      const repoName = 'pubgetRepo';

      setUp(() async {
        mockProcessRunner = MockProcessRunner();
        repoDir = Directory(path.join(oceanWorkspacePath, repoName))
          ..createSync(recursive: true);
        File(path.join(repoDir.path, 'dummy.txt')).writeAsStringSync('data');
        ticketDir = Directory(
          path.join(tempDir.path, ggMultiLegacyTicketFolder, 'TICKET-PUBGET'),
        )..createSync(recursive: true);
        final mockDoCommit = MockGgSystemCommit();
        when(
          () => mockDoCommit.commit(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            paths: any(named: 'paths'),
            includeUntracked: any(named: 'includeUntracked'),
            ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
            userCommitMessage: any(named: 'userCommitMessage'),
            stateKey: any(named: 'stateKey'),
            keepForeignChanges: any(named: 'keepForeignChanges'),
          ),
        ).thenAnswer(
          (_) async => const gg.GgSystemCommitResult(
            userCommitCreated: false,
            systemCommitCreated: true,
            ggOwnedPaths: ['pubspec_overrides.yaml'],
            foreignPaths: [],
          ),
        );
        when(
          () => mockProcessRunner(
            'git',
            ['fetch'],
            workingDirectory: repoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProcessRunner(
            'git',
            ['remote', 'set-head', 'origin', '--auto'],
            workingDirectory: repoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProcessRunner(
            'git',
            ['reset', '--hard', 'origin/main'],
            workingDirectory: repoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProcessRunner(
            'git',
            ['tag', '-l'],
            workingDirectory: repoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
        when(
          () => mockProcessRunner(
            'git',
            ['fetch', '--tags'],
            workingDirectory: repoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProcessRunner(
            'git',
            ['fetch', '--prune', '--tags'],
            workingDirectory: repoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProcessRunner(
            'git',
            ['status', '--porcelain', '--untracked-files=no'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
        createRunner(
          executionPath: ticketDir.path,
          processRunner: mockProcessRunner.call,
          systemCommit: mockDoCommit,
        );
      });

      tearDown(() async {
        if (ticketDir.existsSync()) {
          ticketDir.deleteSync(recursive: true);
        }
      });

      test(
        'executes dart pub get if pubspec.yaml exists and logs success',
        () async {
          File(path.join(repoDir.path, 'pubspec.yaml'))
              .writeAsStringSync('name: pubgetRepo');
          when(
            () => mockProcessRunner(
              'dart',
              ['pub', 'get'],
              workingDirectory: any(named: 'workingDirectory'),
              runInShell: true,
            ),
          ).thenAnswer((_) async => ProcessResult(1, 0, 'Pub get success', ''));
          when(
            () => mockProcessRunner(
              'dart',
              ['pub', 'upgrade'],
              workingDirectory: any(named: 'workingDirectory'),
              runInShell: true,
            ),
          ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));

          await runner.run(['add', '--verbose', repoName]);

          verify(
            () => mockProcessRunner(
              'dart',
              ['pub', 'get'],
              workingDirectory: path.join(ticketDir.path, repoName),
              runInShell: true,
            ),
          ).called(1);
          expect(logMessages, contains('Executed dart pub get in $repoName.'));
        },
      );

      test('logs error if dart pub get fails', () async {
        File(path.join(repoDir.path, 'pubspec.yaml'))
            .writeAsStringSync('name: pubgetRepo');
        when(
          () => mockProcessRunner(
            'dart',
            ['pub', 'get'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(2, 1, '', 'Pub get error'));
        when(
          () => mockProcessRunner(
            'dart',
            ['pub', 'upgrade'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));

        await runner.run(['add', '--verbose', repoName]);

        expect(
          logMessages.any(
            (m) => m.contains(
              'Failed to execute dart pub get '
              'in $repoName: Pub get error',
            ),
          ),
          isTrue,
        );
      });

      test('executes npm install for a TypeScript repo', () async {
        File(path.join(repoDir.path, 'package.json'))
            .writeAsStringSync('{"name": "pubgetRepo", "version": "1.0.0"}');
        File(path.join(repoDir.path, 'tsconfig.json')).writeAsStringSync('{}');
        when(
          () => mockProcessRunner(
            'npm',
            ['install'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'added 1 package', ''));

        await runner.run(['add', '--verbose', repoName]);

        // npm install runs twice: after copy and after localizing.
        verify(
          () => mockProcessRunner(
            'npm',
            ['install'],
            workingDirectory: path.join(ticketDir.path, repoName),
            runInShell: true,
          ),
        ).called(2);
        expect(logMessages, contains('Executed npm install in $repoName.'));
      });
    });

    group('cross-language', () {
      test(
        'transitive scan clones a scoped npm dependency of a known org',
        () async {
          // Covers the npm scan branch of `_cloneMissingTransitiveDeps`.
          // Register a known organization so the npm scope resolves.
          File(path.join(oceanWorkspacePath, '.organizations'))
              .writeAsStringSync(
                '[{"name":"tssuite","url":"https://github.com/tssuite/"}]',
              );

          // A simple Dart repo is the add target ...
          const targetName = 'npm_scan_target';
          final targetDir = Directory(path.join(oceanWorkspacePath, targetName))
            ..createSync(recursive: true);
          File(path.join(targetDir.path, 'pubspec.yaml')).writeAsStringSync(
            // The scan walks what the target reaches, so the consumer below
            // is pulled in as its dependency.
            'name: $targetName\nversion: 1.0.0\n'
            'dependencies:\n  npm_consumer: ^1.0.0\n',
          );

          // ... the TypeScript repo it depends on gets its package.json
          // scanned for cross-language deps. The dependency entries cover
          // every branch of the scan.
          const consumerName = 'npm_consumer';
          final consumerDir = Directory(
            path.join(oceanWorkspacePath, consumerName),
          )..createSync(recursive: true);
          File(path.join(consumerDir.path, 'package.json'))
              .writeAsStringSync('''
{
  "name": "@tssuite/$consumerName",
  "version": "1.0.0",
  "dependencies": {
    "plainpkg": "^1.0.0",
    "@/y": "^1.0.0",
    "@tssuite/": "^1.0.0",
    "@other/skipscope": "^1.0.0",
    "@tssuite/needed_bridge": "^1.0.0",
    "@tssuite/$consumerName": "^1.0.0"
  },
  "devDependencies": {
    "@tssuite/needed_bridge": "^2.0.0"
  }
}
''');

          final ticketDir = Directory(
            path.join(
              tempDir.path,
              ggMultiLegacyTicketFolder,
              'NPM_SCAN_TICKET',
            ),
          )..createSync(recursive: true);

          final mockProc = MockProcessRunner();
          when(
            () => mockProc(
              any(),
              any(),
              workingDirectory: any(named: 'workingDirectory'),
              runInShell: any(named: 'runInShell'),
            ),
          ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

          final mockDoCommit = MockGgSystemCommit();
          when(
            () => mockDoCommit.commit(
              directory: any(named: 'directory'),
              ggLog: any(named: 'ggLog'),
              message: any(named: 'message'),
              paths: any(named: 'paths'),
              includeUntracked: any(named: 'includeUntracked'),
              ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
              userCommitMessage: any(named: 'userCommitMessage'),
              stateKey: any(named: 'stateKey'),
              keepForeignChanges: any(named: 'keepForeignChanges'),
            ),
          ).thenAnswer(
            (_) async => const gg.GgSystemCommitResult(
              userCommitCreated: false,
              systemCommitCreated: true,
              ggOwnedPaths: ['pubspec_overrides.yaml'],
              foreignPaths: [],
            ),
          );

          when(
            () => mockProc(
              'git',
              ['status', '--porcelain', '--untracked-files=no'],
              workingDirectory: any(named: 'workingDirectory'),
              runInShell: true,
            ),
          ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
          createRunner(
            executionPath: ticketDir.path,
            processRunner: mockProc.call,
            systemCommit: mockDoCommit,
          );

          await runner.run(['add', targetName]);

          // The scoped dep of the known org is cloned (via org-fallback URL).
          verify(
            () => mockGitCloner.cloneRepo(
              any(that: contains('needed_bridge')),
              any(),
            ),
          ).called(greaterThanOrEqualTo(1));

          // Unscoped and unknown-org deps are ignored.
          verifyNever(
            () => mockGitCloner.cloneRepo(
              any(that: contains('skipscope')),
              any(),
            ),
          );
          verifyNever(
            () =>
                mockGitCloner.cloneRepo(any(that: contains('plainpkg')), any()),
          );
        },
      );

      test('names dependency, manifest and --no-transitive when a dependency '
          'has no repository', () async {
        // Covers `_missingDependencyHint`: a dependency whose package name
        // does not match any repository - e.g. a renamed package - must
        // point at the manifest that declares it, not just at the name.
        File(path.join(oceanWorkspacePath, '.organizations')).writeAsStringSync(
          '[{"name":"tssuite","url":"https://github.com/tssuite/"}]',
        );

        const targetName = 'hint_target';
        final targetDir = Directory(path.join(oceanWorkspacePath, targetName))
          ..createSync(recursive: true);
        File(path.join(targetDir.path, 'pubspec.yaml')).writeAsStringSync(
          'name: $targetName\nversion: 1.0.0\n'
          'dependencies:\n  hint_consumer: ^1.0.0\n',
        );

        // The consumer declares a dependency that does not exist as repo.
        const consumerName = 'hint_consumer';
        final consumerDir = Directory(
          path.join(oceanWorkspacePath, consumerName),
        )..createSync(recursive: true);
        final manifestPath = path.join(consumerDir.path, 'package.json');
        File(manifestPath).writeAsStringSync('''
{
  "name": "@tssuite/$consumerName",
  "version": "1.0.0",
  "dependencies": {
    "@tssuite/gone-dna": "^1.0.0"
  }
}
''');

        // Every clone of the missing dependency fails.
        when(
          () => mockGitCloner.cloneRepo(any(that: contains('gone-dna')), any()),
        ).thenThrow(Exception('not found'));

        final ticketDir = Directory(
          path.join(tempDir.path, ggMultiLegacyTicketFolder, 'HINT_TICKET'),
        )..createSync(recursive: true);

        createRunner(executionPath: ticketDir.path);

        await runner.run(['add', targetName]);

        final log = logMessages.join('\n');
        expect(
          log,
          contains(
            'The dependency "@tssuite/gone-dna" is not '
            'available',
          ),
        );
        expect(log, contains('(tssuite)'));
        expect(log, contains('It is declared in: $manifestPath'));
        expect(log, contains('--no-transitive'));

        // The manifest was read from a checkout that had been brought to
        // its remote default branch first, so the report can rule out a
        // stale copy.
        expect(log, contains('on the state of origin/<default branch>'));
      });

      test('says so when the manifest was not refreshed', () async {
        File(path.join(oceanWorkspacePath, '.organizations')).writeAsStringSync(
          '[{"name":"tssuite","url":"https://github.com/tssuite/"}]',
        );

        const targetName = 'nofetch_target';
        final targetDir = Directory(path.join(oceanWorkspacePath, targetName))
          ..createSync(recursive: true);
        File(path.join(targetDir.path, 'pubspec.yaml')).writeAsStringSync(
          'name: $targetName\nversion: 1.0.0\n'
          'dependencies:\n  nofetch_consumer: ^1.0.0\n',
        );

        const consumerName = 'nofetch_consumer';
        final consumerDir = Directory(
          path.join(oceanWorkspacePath, consumerName),
        )..createSync(recursive: true);
        File(path.join(consumerDir.path, 'package.json')).writeAsStringSync(
          '{"name":"@tssuite/$consumerName","version":"1.0.0",'
          '"dependencies":{"@tssuite/gone-dna":"^1.0.0"}}',
        );

        when(
          () => mockGitCloner.cloneRepo(any(that: contains('gone-dna')), any()),
        ).thenThrow(Exception('not found'));

        final ticketDir = Directory(
          path.join(tempDir.path, ggMultiLegacyTicketFolder, 'NOFETCH_TICKET'),
        )..createSync(recursive: true);

        createRunner(executionPath: ticketDir.path);

        await runner.run(['add', targetName, '--no-fetch']);

        expect(
          logMessages.join('\n'),
          contains('was not refreshed (--no-fetch)'),
        );
      });

      test(
        'a package.json that is not a JSON object is ignored by the scan',
        () async {
          // Covers the "decoded is not a Map" guard of the npm scan.
          const consumerName = 'npm_array_consumer';
          final consumerDir = Directory(
            path.join(oceanWorkspacePath, consumerName),
          )..createSync(recursive: true);
          File(path.join(consumerDir.path, 'package.json'))
              .writeAsStringSync('["not", "an", "object"]');

          const targetName = 'array_target';
          final targetDir = Directory(path.join(oceanWorkspacePath, targetName))
            ..createSync(recursive: true);
          File(path.join(targetDir.path, 'pubspec.yaml')).writeAsStringSync(
            'name: $targetName\nversion: 1.0.0\n'
            'dependencies:\n  npm_array_consumer: ^1.0.0\n',
          );

          final ticketDir = Directory(
            path.join(tempDir.path, ggMultiLegacyTicketFolder, 'ARRAY_TICKET'),
          )..createSync(recursive: true);

          final mockProc = MockProcessRunner();
          when(
            () => mockProc(
              any(),
              any(),
              workingDirectory: any(named: 'workingDirectory'),
              runInShell: any(named: 'runInShell'),
            ),
          ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

          final mockDoCommit = MockGgSystemCommit();
          when(
            () => mockDoCommit.commit(
              directory: any(named: 'directory'),
              ggLog: any(named: 'ggLog'),
              message: any(named: 'message'),
              paths: any(named: 'paths'),
              includeUntracked: any(named: 'includeUntracked'),
              ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
              userCommitMessage: any(named: 'userCommitMessage'),
              stateKey: any(named: 'stateKey'),
              keepForeignChanges: any(named: 'keepForeignChanges'),
            ),
          ).thenAnswer(
            (_) async => const gg.GgSystemCommitResult(
              userCommitCreated: false,
              systemCommitCreated: true,
              ggOwnedPaths: ['pubspec_overrides.yaml'],
              foreignPaths: [],
            ),
          );

          when(
            () => mockProc(
              'git',
              ['status', '--porcelain', '--untracked-files=no'],
              workingDirectory: any(named: 'workingDirectory'),
              runInShell: true,
            ),
          ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
          createRunner(
            executionPath: ticketDir.path,
            processRunner: mockProc.call,
            systemCommit: mockDoCommit,
          );

          // Must not throw despite the malformed package.json.
          await runner.run(['add', targetName]);
        },
      );

      test(
        'installs both Dart and TypeScript dependencies for a bridge repo',
        () async {
          // Covers running both package managers for a dual-manifest repo.
          const repoName = 'bridgeRepo';
          final repoDir = Directory(path.join(oceanWorkspacePath, repoName))
            ..createSync(recursive: true);
          File(path.join(repoDir.path, 'pubspec.yaml'))
              .writeAsStringSync('name: $repoName\nversion: 1.0.0\n');
          File(path.join(repoDir.path, 'package.json')).writeAsStringSync(
            '{"name": "@scope/$repoName", "version": "1.0.0"}',
          );
          File(path.join(repoDir.path, 'tsconfig.json'))
              .writeAsStringSync('{}');

          final ticketDir = Directory(
            path.join(tempDir.path, ggMultiLegacyTicketFolder, 'BRIDGE_TICKET'),
          )..createSync(recursive: true);

          final mockProc = MockProcessRunner();
          when(
            () => mockProc(
              any(),
              any(),
              workingDirectory: any(named: 'workingDirectory'),
              runInShell: any(named: 'runInShell'),
            ),
          ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

          final mockDoCommit = MockGgSystemCommit();
          when(
            () => mockDoCommit.commit(
              directory: any(named: 'directory'),
              ggLog: any(named: 'ggLog'),
              message: any(named: 'message'),
              paths: any(named: 'paths'),
              includeUntracked: any(named: 'includeUntracked'),
              ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
              userCommitMessage: any(named: 'userCommitMessage'),
              stateKey: any(named: 'stateKey'),
              keepForeignChanges: any(named: 'keepForeignChanges'),
            ),
          ).thenAnswer(
            (_) async => const gg.GgSystemCommitResult(
              userCommitCreated: false,
              systemCommitCreated: true,
              ggOwnedPaths: ['pubspec_overrides.yaml'],
              foreignPaths: [],
            ),
          );

          when(
            () => mockProc(
              'git',
              ['status', '--porcelain', '--untracked-files=no'],
              workingDirectory: any(named: 'workingDirectory'),
              runInShell: true,
            ),
          ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
          createRunner(
            executionPath: ticketDir.path,
            processRunner: mockProc.call,
            systemCommit: mockDoCommit,
          );

          await runner.run(['add', repoName]);

          final ticketRepo = path.join(ticketDir.path, repoName);
          // After copy: both dart pub get and npm install run.
          verify(
            () => mockProc(
              'dart',
              ['pub', 'get'],
              workingDirectory: ticketRepo,
              runInShell: true,
            ),
          ).called(1);
          verify(
            () => mockProc(
              'npm',
              ['install'],
              workingDirectory: ticketRepo,
              runInShell: true,
            ),
          ).called(greaterThanOrEqualTo(1));
          // After localizing: dart pub upgrade also runs.
          verify(
            () => mockProc(
              'dart',
              ['pub', 'upgrade'],
              workingDirectory: ticketRepo,
              runInShell: true,
            ),
          ).called(1);
        },
      );
    });

    test('commit failures are logged and end the run', () async {
      const repoName = 'commitFailRepo';
      final repoDir = Directory(path.join(oceanWorkspacePath, repoName))
        ..createSync(recursive: true);
      File(path.join(repoDir.path, 'dummy.txt')).writeAsStringSync('data');
      File(path.join(repoDir.path, 'pubspec.yaml'))
          .writeAsStringSync('name: x');

      final ticketDir = Directory(
        path.join(
          tempDir.path,
          ggMultiLegacyTicketFolder,
          'TICKET-COMMIT-FAIL',
        ),
      )..createSync(recursive: true);

      // The ticket already holds a git checkout of the repo.
      await gitTicketRepo(ticketDir, repoName, 'name: x\n');

      final mockDoCommit = MockGgSystemCommit();
      when(
        () => mockDoCommit.commit(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          paths: any(named: 'paths'),
          includeUntracked: any(named: 'includeUntracked'),
          ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
          userCommitMessage: any(named: 'userCommitMessage'),
          stateKey: any(named: 'stateKey'),
          keepForeignChanges: any(named: 'keepForeignChanges'),
        ),
      ).thenThrow(Exception('commit error'));

      final mockProc = MockProcessRunner();
      when(
        () => mockProc(
          'git',
          any(),
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'git',
          ['fetch'],
          workingDirectory: repoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'git',
          ['remote', 'set-head', 'origin', '--auto'],
          workingDirectory: repoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'git',
          ['reset', '--hard', 'origin/main'],
          workingDirectory: repoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'git',
          ['tag', '-l'],
          workingDirectory: repoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => mockProc(
          'git',
          ['fetch', '--tags'],
          workingDirectory: repoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'git',
          ['fetch', '--prune', '--tags'],
          workingDirectory: repoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'dart',
          ['pub', 'get'],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
      when(
        () => mockProc(
          'dart',
          ['pub', 'upgrade'],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));

      when(
        () => mockProc(
          'git',
          ['status', '--porcelain', '--untracked-files=no'],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      createRunner(
        executionPath: ticketDir.path,
        systemCommit: mockDoCommit,
        processRunner: mockProc.call,
      );

      await expectLater(
        runner.run(['add', '--verbose', repoName]),
        throwsA(
          isA<Exception>().having(
            (e) => rmControls('$e'),
            'message',
            contains('Failed to commit the localized refs of $repoName'),
          ),
        ),
      );

      expect(
        logMessages.any(
          (m) =>
              m.contains('Failed to commit $repoName: Exception: commit error'),
        ),
        isTrue,
      );
    });

    test(
      'clones multiple repositories when multiple targets provided',
      () async {
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        final mockDoCommit = MockGgSystemCommit();
        when(
          () => mockDoCommit.commit(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            paths: any(named: 'paths'),
            includeUntracked: any(named: 'includeUntracked'),
            ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
            userCommitMessage: any(named: 'userCommitMessage'),
            stateKey: any(named: 'stateKey'),
            keepForeignChanges: any(named: 'keepForeignChanges'),
          ),
        ).thenAnswer(
          (_) async => const gg.GgSystemCommitResult(
            userCommitCreated: false,
            systemCommitCreated: true,
            ggOwnedPaths: ['pubspec_overrides.yaml'],
            foreignPaths: [],
          ),
        );

        createRunner(systemCommit: mockDoCommit);

        await runner.run(['add', 'repoA', 'repoB']);
        verify(
          () =>
              mockGitCloner.cloneRepo('git@github.com:repoA/repoA.git', any()),
        ).called(1);
        verify(
          () =>
              mockGitCloner.cloneRepo('git@github.com:repoB/repoB.git', any()),
        ).called(1);
        expect(
          logMessages,
          anyElement(contains('repoA from git@github.com:repoA/repoA.git')),
        );
        expect(
          logMessages,
          anyElement(contains('repoB from git@github.com:repoB/repoB.git')),
        );
      },
    );

    test('localization aborts and logs when localize fails', () async {
      const repoName = 'localizeFailRepo';
      final repoDir = Directory(path.join(oceanWorkspacePath, repoName))
        ..createSync(recursive: true);
      File(path.join(repoDir.path, 'pubspec.yaml'))
          .writeAsStringSync('name: $repoName');

      final ticketDir = Directory(
        path.join(tempDir.path, ggMultiLegacyTicketFolder, 'TICKET-LOCFAIL'),
      )..createSync(recursive: true);

      final mockSorted = MockSortedProcessingList();
      final mockLoc = MockLocalizeRefs();
      final mockDoCommit = MockGgSystemCommit();

      when(
        () => mockDoCommit.commit(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          paths: any(named: 'paths'),
          includeUntracked: any(named: 'includeUntracked'),
          ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
          userCommitMessage: any(named: 'userCommitMessage'),
          stateKey: any(named: 'stateKey'),
          keepForeignChanges: any(named: 'keepForeignChanges'),
        ),
      ).thenAnswer(
        (_) async => const gg.GgSystemCommitResult(
          userCommitCreated: false,
          systemCommitCreated: true,
          ggOwnedPaths: ['pubspec_overrides.yaml'],
          foreignPaths: [],
        ),
      );

      Future<List<Node>> futureNode() async => [
        Node(
          name: repoName,
          directory: Directory(path.join(ticketDir.path, repoName)),
          manifest: DartPackageManifest(pubspec: Pubspec(repoName)),
        ),
      ];

      when(
        () => mockSorted.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async => await futureNode());

      when(
        () => mockLoc.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenThrow(Exception('localize failed'));

      final mockRunner = MockProcessRunner();
      when(
        () => mockRunner(
          'git',
          any(),
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
      when(
        () => mockRunner(
          'dart',
          ['pub', 'get'],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
      when(
        () => mockRunner(
          'dart',
          ['pub', 'upgrade'],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));

      when(
        () => mockRunner(
          'git',
          ['status', '--porcelain', '--untracked-files=no'],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      createRunner(
        executionPath: ticketDir.path,
        processRunner: mockRunner.call,
        systemCommit: mockDoCommit,
        sortedProcessingList: mockSorted,
        localizeRefs: mockLoc,
      );

      await expectLater(
        () async => await runner.run(['add', '--verbose', repoName]),
        throwsA(isA<Exception>()),
      );

      expect(
        logMessages.any(
          (m) => m.contains(
            'Failed to localize refs for $repoName: '
            'Exception: localize failed',
          ),
        ),
        isTrue,
      );
    });

    test(
      'adds between nodes into ticket when executed inside a ticket',
      () async {
        final aDir = Directory(path.join(oceanWorkspacePath, 'a'))
          ..createSync(recursive: true);
        final bDir = Directory(path.join(oceanWorkspacePath, 'b'))
          ..createSync(recursive: true);
        final cDir = Directory(path.join(oceanWorkspacePath, 'c'))
          ..createSync(recursive: true);

        File(path.join(aDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: a
version: 1.0.0
dependencies:
  b: ^1.0.0
''');
        File(path.join(bDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: b
version: 1.0.0
dependencies:
  c: ^1.0.0
''');
        File(path.join(cDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: c
version: 1.0.0
''');

        final ticketDir = Directory(
          path.join(tempDir.path, ggMultiLegacyTicketFolder, 'TXYZ'),
        )..createSync(recursive: true);

        final mockRunner = MockProcessRunner();
        when(
          () => mockRunner(
            'git',
            any(),
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
        when(
          () => mockRunner(
            'dart',
            ['pub', 'get'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
        when(
          () => mockRunner(
            'dart',
            ['pub', 'upgrade'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));

        final mockDoCommit = MockGgSystemCommit();
        when(
          () => mockDoCommit.commit(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            paths: any(named: 'paths'),
            includeUntracked: any(named: 'includeUntracked'),
            ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
            userCommitMessage: any(named: 'userCommitMessage'),
            stateKey: any(named: 'stateKey'),
            keepForeignChanges: any(named: 'keepForeignChanges'),
          ),
        ).thenAnswer(
          (_) async => const gg.GgSystemCommitResult(
            userCommitCreated: false,
            systemCommitCreated: true,
            ggOwnedPaths: ['pubspec_overrides.yaml'],
            foreignPaths: [],
          ),
        );

        when(
          () => mockRunner(
            'git',
            ['status', '--porcelain', '--untracked-files=no'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
        createRunner(
          executionPath: ticketDir.path,
          processRunner: mockRunner.call,
          systemCommit: mockDoCommit,
        );

        await runner.run(['add', '--verbose', 'a', 'c']);

        expect(Directory(path.join(ticketDir.path, 'a')).existsSync(), isTrue);
        expect(Directory(path.join(ticketDir.path, 'b')).existsSync(), isTrue);
        expect(Directory(path.join(ticketDir.path, 'c')).existsSync(), isTrue);

        expect(
          logMessages.any(
            (m) => m == 'Added repository b to ticket workspace.',
          ),
          isTrue,
        );

        expect(
          logMessages.any(
            (m) => m.contains(
              'Localized the references of all repos in ticket TXYZ',
            ),
          ),
          isTrue,
        );

        final workspaceFile = File(
          path.join(ticketDir.path, 'TXYZ.code-workspace'),
        );
        expect(workspaceFile.existsSync(), isTrue);
        final workspaceJson = jsonDecode(
          workspaceFile.readAsStringSync(),
        ) as Map<String, dynamic>;
        final folders = (workspaceJson['folders'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        final folderPaths = folders.map((f) => f['path'] as String).toSet();
        expect(folderPaths, equals(<String>{'a', 'b', 'c'}));
      },
    );

    test(
      '--no-transitive leaves the between nodes out of the ticket',
      () async {
        final aDir = Directory(path.join(oceanWorkspacePath, 'a'))
          ..createSync(recursive: true);
        final bDir = Directory(path.join(oceanWorkspacePath, 'b'))
          ..createSync(recursive: true);
        final cDir = Directory(path.join(oceanWorkspacePath, 'c'))
          ..createSync(recursive: true);

        File(path.join(aDir.path, 'pubspec.yaml')).writeAsStringSync(
          [
            'name: a',
            'version: 1.0.0',
            'dependencies:',
            '  b: ^1.0.0',
            '',
          ].join('\n'),
        );
        File(path.join(bDir.path, 'pubspec.yaml')).writeAsStringSync(
          [
            'name: b',
            'version: 1.0.0',
            'dependencies:',
            '  c: ^1.0.0',
            '',
          ].join('\n'),
        );
        File(path.join(cDir.path, 'pubspec.yaml'))
            .writeAsStringSync(['name: c', 'version: 1.0.0', ''].join('\n'));

        final ticketDir = Directory(
          path.join(tempDir.path, ggMultiLegacyTicketFolder, 'TXYZ'),
        )..createSync(recursive: true);

        final mockRunner = MockProcessRunner();
        when(
          () => mockRunner(
            'git',
            any(),
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
        when(
          () => mockRunner(
            'dart',
            ['pub', 'get'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
        when(
          () => mockRunner(
            'dart',
            ['pub', 'upgrade'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));

        final mockDoCommit = MockGgSystemCommit();
        when(
          () => mockDoCommit.commit(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            paths: any(named: 'paths'),
            includeUntracked: any(named: 'includeUntracked'),
            ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
            userCommitMessage: any(named: 'userCommitMessage'),
            stateKey: any(named: 'stateKey'),
            keepForeignChanges: any(named: 'keepForeignChanges'),
          ),
        ).thenAnswer(
          (_) async => const gg.GgSystemCommitResult(
            userCommitCreated: false,
            systemCommitCreated: true,
            ggOwnedPaths: ['pubspec_overrides.yaml'],
            foreignPaths: [],
          ),
        );

        when(
          () => mockRunner(
            'git',
            ['status', '--porcelain', '--untracked-files=no'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
        createRunner(
          executionPath: ticketDir.path,
          processRunner: mockRunner.call,
          systemCommit: mockDoCommit,
        );

        await runner.run(['add', '--verbose', '--no-transitive', 'a', 'c']);

        expect(Directory(path.join(ticketDir.path, 'a')).existsSync(), isTrue);
        expect(Directory(path.join(ticketDir.path, 'c')).existsSync(), isTrue);

        // b lies between a and c and is therefore not copied.
        expect(Directory(path.join(ticketDir.path, 'b')).existsSync(), isFalse);

        expect(
          logMessages.any(
            (m) =>
                m.contains('Skip adding transitive repos (--no-transitive).'),
          ),
          isTrue,
        );

        final workspaceFile = File(
          path.join(ticketDir.path, 'TXYZ.code-workspace'),
        );
        expect(workspaceFile.existsSync(), isTrue);
        final workspaceJson = jsonDecode(
          workspaceFile.readAsStringSync(),
        ) as Map<String, dynamic>;
        final folders = (workspaceJson['folders'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        final folderPaths = folders.map((f) => f['path'] as String).toSet();
        expect(folderPaths, equals(<String>{'a', 'c'}));
      },
    );

    group('~/.gg_rc and gg do add transitive', () {
      late Directory ticketDir;

      /// An ocean a -> b -> c and an empty ticket TXYZ.
      setUp(() {
        for (final (name, dep) in [('a', 'b'), ('b', 'c'), ('c', null)]) {
          File(path.join(oceanWorkspacePath, name, 'pubspec.yaml'))
            ..createSync(recursive: true)
            ..writeAsStringSync(
              [
                'name: $name',
                'version: 1.0.0',
                if (dep != null) ...['dependencies:', '  $dep: ^1.0.0'],
                '',
              ].join('\n'),
            );
        }
        ticketDir = Directory(
          path.join(tempDir.path, ggMultiLegacyTicketFolder, 'TXYZ'),
        )..createSync(recursive: true);
      });

      /// A runner adding to the ticket, git and pub stubbed.
      void ticketRunner({GgRc? ggRc, ReposBetween? reposBetween}) {
        final mockRunner = MockProcessRunner();
        when(
          () => mockRunner(
            any(),
            any(),
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: any(named: 'runInShell'),
            environment: any(named: 'environment'),
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, '', ''));
        final mockDoCommit = MockGgSystemCommit();
        when(
          () => mockDoCommit.commit(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            paths: any(named: 'paths'),
            includeUntracked: any(named: 'includeUntracked'),
            ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
            userCommitMessage: any(named: 'userCommitMessage'),
            stateKey: any(named: 'stateKey'),
            keepForeignChanges: any(named: 'keepForeignChanges'),
          ),
        ).thenAnswer(
          (_) async => const gg.GgSystemCommitResult(
            userCommitCreated: false,
            systemCommitCreated: true,
            ggOwnedPaths: [],
            foreignPaths: [],
          ),
        );
        createRunner(
          executionPath: ticketDir.path,
          processRunner: mockRunner.call,
          systemCommit: mockDoCommit,
          ggRc: ggRc,
          reposBetween: reposBetween,
        );
      }

      bool inTicket(String name) =>
          Directory(path.join(ticketDir.path, name)).existsSync();

      final rcFile = File(path.join('home', '.gg_rc'));
      final lean = GgRc(
        values: const {
          'do': {
            'add': {'transitive': false},
          },
        },
        file: rcFile,
      );

      test('~/.gg_rc leaves the repos between out, and says so', () async {
        ticketRunner(ggRc: lean);

        await runner.run(['add', 'a', 'c']);

        expect(
          [inTicket('a'), inTicket('b'), inTicket('c')],
          [true, false, true],
        );
        expect(
          logMessages,
          contains(
            'Skip adding transitive repos (${rcFile.path}: '
            'do.add.transitive = false). A breaking release adds them later: '
            'gg do add transitive for <repo>.',
          ),
        );
      });

      test('names .gg_rc when the settings have no file', () async {
        ticketRunner(
          ggRc: const GgRc(
            values: {
              'do': {
                'add': {'transitive': false},
              },
            },
          ),
        );

        await runner.run(['add', 'a', 'c']);

        expect(
          logMessages,
          contains(startsWith('Skip adding transitive repos (.gg_rc: ')),
        );
      });

      test('--transitive beats ~/.gg_rc', () async {
        ticketRunner(ggRc: lean);

        await runner.run(['add', '--transitive', 'a', 'c']);

        expect(inTicket('b'), isTrue);
      });

      test('transitive for <repo> adds the repos between it and the ticket '
          'repos depending on it', () async {
        ticketRunner(ggRc: lean);
        await runner.run(['add', 'a', 'c']);
        logMessages.clear();

        await runner.run(['add', 'transitive', 'for', 'c']);

        expect(inTicket('b'), isTrue);
        expect(
          logMessages,
          contains(
            '\n✓ Adding the repos between the '
            'ticket and c',
          ),
        );
        expect(logMessages, contains('  ✓ b'));
        expect(logMessages.last, '✔ Successfully added b');
      });

      test('transitive for a repo nothing in the ticket depends on through '
          'the ocean adds nothing', () async {
        ticketRunner(ggRc: lean);
        await runner.run(['add', 'a', 'c']);
        logMessages.clear();

        await runner.run(['add', 'transitive', 'for', 'a']);

        expect(inTicket('b'), isFalse);
        expect(logMessages.last, '✔ No repos missing between them');
      });

      test('transitive without for asks about every ticket repo', () async {
        ticketRunner(ggRc: lean);
        await runner.run(['add', 'a', 'c']);

        await runner.run(['add', 'transitive']);

        expect(inTicket('b'), isTrue);
        expect(
          logMessages,
          contains(
            '\n✓ Adding the repos between the ticket and the ticket '
            'repos',
          ),
        );
      });

      test('transitive for without a repo is a usage error', () async {
        ticketRunner();

        for (final args in [
          ['add', 'transitive', 'for'],
          ['add', 'transitive', 'c'],
        ]) {
          await expectLater(
            runner.run(args),
            throwsA(
              isA<UsageException>().having(
                (e) => e.message,
                'message',
                contains('gg do add transitive for <repo> [<repo>…]'),
              ),
            ),
          );
        }
      });

      test(
        'transitive for a repo outside the ticket says how to add it',
        () async {
          ticketRunner(ggRc: lean);
          await runner.run(['add', 'a']);

          await expectLater(
            runner.run(['add', 'transitive', 'for', 'x', 'c']),
            throwsA(
              isA<Exception>().having(
                (e) => rmControls('$e'),
                'message',
                'Exception: c x are not in the ticket. '
                    'Add them first with gg do add c x.',
              ),
            ),
          );
          await expectLater(
            runner.run(['add', 'transitive', 'for', 'c']),
            throwsA(
              isA<Exception>().having(
                (e) => rmControls('$e'),
                'message',
                'Exception: c is not in the ticket. '
                    'Add it first with gg do add c.',
              ),
            ),
          );
        },
      );

      test('transitive needs a ticket', () async {
        createRunner(executionPath: tempDir.path);

        await expectLater(
          runner.run(['add', 'transitive', 'for', 'c']),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              contains('only be used from inside a ticket workspace'),
            ),
          ),
        );
      });

      test('a broken ~/.gg_rc stops only a run that reads it', () async {
        final broken = File(path.join(tempDir.path, 'broken_rc'))
          ..writeAsStringSync('{');
        ticketRunner(
          ggRc: GgRc.load(ggLog: ggLog, file: broken),
        );

        await runner.run(['add', '--no-transitive', 'a', 'c']);
        expect(inTicket('b'), isFalse);

        await expectLater(
          runner.run(['add', 'a']),
          throwsA(
            isA<Exception>().having(
              (e) => rmControls('$e'),
              'message',
              contains('is no valid JSON'),
            ),
          ),
        );
      });

      test('selects the releases by pattern', () async {
        ticketRunner(ggRc: lean);
        await runner.run(['add', 'a', 'c']);

        await runner.run(['add', 'transitive', 'for', '[c]']);

        expect(inTicket('b'), isTrue);
        expect(
          logMessages,
          contains('\n✓ Adding the repos between the ticket and c'),
        );
      });

      test('fails for an ocean graph that does not build', () async {
        final reposBetween = MockReposBetween();
        when(
          () => reposBetween.find(
            ticketPath: any(named: 'ticketPath'),
            oceanPath: any(named: 'oceanPath'),
            from: any(named: 'from'),
          ),
        ).thenAnswer((_) async => (names: <String>[], error: 'a cycle'));
        ticketRunner(ggRc: lean, reposBetween: reposBetween);
        await runner.run(['add', 'c']);

        await expectLater(
          runner.run(['add', 'transitive', 'for', 'c']),
          throwsA(
            isA<Exception>().having(
              (e) => rmControls('$e'),
              'message',
              contains('Could not find the repos between: a cycle'),
            ),
          ),
        );

        expect(
          logMessages,
          contains(
            contains(
              'The dependency graph of the ocean does not '
              'build: a cycle',
            ),
          ),
        );
      });

      test('addReposBetweenWithAddCommand adds what gg do add transitive '
          'for adds', () async {
        await expectLater(
          addReposBetweenWithAddCommand(
            ticketDir: ticketDir,
            releases: {'x'},
            ggLog: ggLog,
          ),
          throwsA(
            isA<Exception>().having(
              (e) => rmControls('$e'),
              'message',
              contains('x is not in the ticket'),
            ),
          ),
        );
      });
    });

    test(
      'adds between nodes using existing ticket repos as endpoints',
      () async {
        final aDir = Directory(path.join(oceanWorkspacePath, 'a'))
          ..createSync(recursive: true);
        final bDir = Directory(path.join(oceanWorkspacePath, 'b'))
          ..createSync(recursive: true);
        final cDir = Directory(path.join(oceanWorkspacePath, 'c'))
          ..createSync(recursive: true);

        File(path.join(aDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: a
version: 1.0.0
dependencies:
  b: ^1.0.0
''');
        File(path.join(bDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: b
version: 1.0.0
dependencies:
  c: ^1.0.0
''');
        File(path.join(cDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: c
version: 1.0.0
''');

        final ticketDir = Directory(
          path.join(tempDir.path, ggMultiLegacyTicketFolder, 'TXYZ_EXISTING'),
        )..createSync(recursive: true);

        final existingC = Directory(path.join(ticketDir.path, 'c'))
          ..createSync(recursive: true);
        File(path.join(existingC.path, 'dummy.txt')).writeAsStringSync('x');
        File(path.join(existingC.path, 'pubspec.yaml'))
            .writeAsStringSync('name: c\nversion: 1.0.0\n');

        final mockRunner = MockProcessRunner();
        when(
          () => mockRunner(
            'git',
            any(),
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
        when(
          () => mockRunner(
            'dart',
            ['pub', 'get'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
        when(
          () => mockRunner(
            'dart',
            ['pub', 'upgrade'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));

        final mockDoCommit = MockGgSystemCommit();
        when(
          () => mockDoCommit.commit(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            paths: any(named: 'paths'),
            includeUntracked: any(named: 'includeUntracked'),
            ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
            userCommitMessage: any(named: 'userCommitMessage'),
            stateKey: any(named: 'stateKey'),
            keepForeignChanges: any(named: 'keepForeignChanges'),
          ),
        ).thenAnswer(
          (_) async => const gg.GgSystemCommitResult(
            userCommitCreated: false,
            systemCommitCreated: true,
            ggOwnedPaths: ['pubspec_overrides.yaml'],
            foreignPaths: [],
          ),
        );

        when(
          () => mockRunner(
            'git',
            ['status', '--porcelain', '--untracked-files=no'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
        createRunner(
          executionPath: ticketDir.path,
          processRunner: mockRunner.call,
          systemCommit: mockDoCommit,
        );

        await runner.run(['add', '--verbose', 'a']);

        expect(Directory(path.join(ticketDir.path, 'a')).existsSync(), isTrue);
        expect(Directory(path.join(ticketDir.path, 'b')).existsSync(), isTrue);
        expect(Directory(path.join(ticketDir.path, 'c')).existsSync(), isTrue);

        expect(
          logMessages.any(
            (m) => m == 'Added repository b to ticket workspace.',
          ),
          isTrue,
        );
        expect(
          logMessages.any((m) => m == 'c already exists in ticket workspace.'),
          isFalse,
        );
        expect(
          logMessages.any(
            (m) => m.contains(
              'Localized the references of all repos in ticket TXYZ_EXISTING',
            ),
          ),
          isTrue,
        );
      },
    );

    group('ticket state', () {
      // A process runner that answers every git/dart call successfully.
      MockProcessRunner anyProcessRunner() {
        final mockProc = MockProcessRunner();
        when(
          () => mockProc(
            any(),
            any(),
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: any(named: 'runInShell'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
        return mockProc;
      }

      void oceanRepo(String name, [String deps = '']) {
        final dir = Directory(path.join(oceanWorkspacePath, name))
          ..createSync(recursive: true);
        File(path.join(dir.path, 'pubspec.yaml'))
            .writeAsStringSync('name: $name\nversion: 1.0.0\n$deps');
      }

      Directory ticket(String name) =>
          Directory(path.join(tempDir.path, name))..createSync();

      test('keeps the user\'s work out of gg\'s commit', () async {
        oceanRepo('b');
        final ticketDir = ticket('T_WIP');
        File(path.join(ticketDir.path, 'ticket.json'))
            .writeAsStringSync('{"issue_id": "T_WIP"}');
        final a = await gitTicketRepo(
          ticketDir,
          'a',
          'name: a\nversion: 1.0.0\nenvironment:\n  sdk: ^3.0.0\n',
        );

        // Unfinished work: a new dependency and a new file.
        final pubspec = File(path.join(a.path, 'pubspec.yaml'));
        pubspec.writeAsStringSync(
          '${pubspec.readAsStringSync()}dependencies:\n  b: ^1.0.0\n',
        );
        File(path.join(a.path, 'wip.dart')).writeAsStringSync('// wip');

        createRunner(
          executionPath: ticketDir.path,
          processRunner: anyProcessRunner().call,
        );
        await runner.run(['add', 'b']);

        // gg's override is committed on its own ...
        expect(
          File(path.join(a.path, 'pubspec_overrides.yaml')).readAsStringSync(),
          contains('path: ../b'),
        );
        expect(
          await gitOutput(a, ['log', '--format=%s']),
          '#gg: changed references to path\nInitial commit',
        );
        expect(
          await gitOutput(a, ['show', '--name-only', '--format=', 'HEAD']),
          contains('pubspec_overrides.yaml'),
        );

        // ... the user's work stays uncommitted.
        expect(
          await gitOutput(a, ['status', '--porcelain']),
          'M pubspec.yaml\n?? wip.dart',
        );
      });

      test('commits the repos localized before a failing one', () async {
        // x and y use b, y also x: b, x and y are localized in that order.
        oceanRepo('b');
        final ticketDir = ticket('T_FAIL');
        File(path.join(ticketDir.path, 'ticket.json'))
            .writeAsStringSync('{"issue_id": "T_FAIL"}');
        const sdk = 'environment:\n  sdk: ^3.0.0\n';
        final x = await gitTicketRepo(
          ticketDir,
          'x',
          'name: x\nversion: 1.0.0\n${sdk}dependencies:\n  b: ^1.0.0\n',
        );
        final y = await gitTicketRepo(
          ticketDir,
          'y',
          'name: y\nversion: 1.0.0\n$sdk'
              'dependencies:\n  b: ^1.0.0\n  x: ^1.0.0\n',
        );

        createRunner(
          executionPath: ticketDir.path,
          processRunner: anyProcessRunner().call,
          localizeRefs: FailingChangeRefsToLocal(ggLog: ggLog, failing: 'y'),
        );
        await expectLater(
          runner.run(['add', 'b']),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('Failed to localize the refs of y'),
            ),
          ),
        );

        // x's override is committed, though y failed after it ...
        expect(
          File(path.join(x.path, 'pubspec_overrides.yaml')).readAsStringSync(),
          contains('path: ../b'),
        );
        expect(
          await gitOutput(x, ['log', '--format=%s']),
          '#gg: changed references to path\nInitial commit',
        );
        expect(await gitOutput(x, ['status', '--porcelain']), isEmpty);
        // ... while gg leaves the failed y alone.
        expect(await gitOutput(y, ['log', '--format=%s']), 'Initial commit');
      });

      test('records the commit state of the repos copied now only', () async {
        // b is a git repo of the ocean, copied by this run.
        final b = Directory(path.join(oceanWorkspacePath, 'b'))
          ..createSync(recursive: true);
        File(path.join(b.path, 'pubspec.yaml')).writeAsStringSync(
          'name: b\nversion: 1.0.0\nenvironment:\n  sdk: ^3.0.0\n',
        );
        for (final args in [
          ['init', '-q', '-b', 'main'],
          ['config', 'user.email', 'test@example.com'],
          ['config', 'user.name', 'Test'],
          ['add', '.'],
          ['commit', '-q', '-m', 'Initial commit'],
        ]) {
          await Process.run('git', args, workingDirectory: b.path);
        }
        when(() => mockGitCloner.checkoutBranch(any(), any())).thenAnswer(
          (invocation) => Process.run('git', [
            'checkout',
            '-q',
            '-b',
            invocation.positionalArguments[0] as String,
          ], workingDirectory: invocation.positionalArguments[1] as String),
        );

        // a was in the ticket; its new dependency was committed with plain
        // git, so its checks never ran.
        final ticketDir = ticket('T_STATE');
        File(path.join(ticketDir.path, 'ticket.json'))
            .writeAsStringSync('{"issue_id": "T_STATE"}');
        final a = await gitTicketRepo(
          ticketDir,
          'a',
          'name: a\nversion: 1.0.0\nenvironment:\n  sdk: ^3.0.0\n',
        );
        final pubspec = File(path.join(a.path, 'pubspec.yaml'));
        pubspec.writeAsStringSync(
          '${pubspec.readAsStringSync()}dependencies:\n  b: ^1.0.0\n',
        );
        await gitOutput(a, ['commit', '-qam', 'Use b']);

        createRunner(
          executionPath: ticketDir.path,
          processRunner: anyProcessRunner().call,
        );
        await runner.run(['add', 'b']);

        Future<bool> committed(String repo) =>
            gg.GgState(ggLog: ggLog).readSuccess(
              directory: Directory(path.join(ticketDir.path, repo)),
              key: gg.GgState.doCommitKey,
              ggLog: ggLog,
            );
        expect(
          await gitOutput(a, ['log', '-1', '--format=%s']),
          '#gg: changed references to path',
        );
        expect(await gitOutput(a, ['status', '--porcelain']), isEmpty);
        expect(await committed('a'), isFalse);
        expect(await committed('b'), isTrue);
      });

      test('adds the repos between the ticket repos along an edge only the '
          'ticket has', () async {
        oceanRepo('a');
        oceanRepo('c', 'dependencies:\n  d: ^1.0.0\n');
        oceanRepo('d');

        // On its feature branch, a newly depends on c.
        final ticketDir = ticket('T_EDGE');
        File(path.join(ticketDir.path, 'ticket.json'))
            .writeAsStringSync('{"issue_id": "T_EDGE"}');
        final a = Directory(path.join(ticketDir.path, 'a'))..createSync();
        File(path.join(a.path, 'pubspec.yaml')).writeAsStringSync(
          'name: a\nversion: 1.0.0\ndependencies:\n  c: ^1.0.0\n',
        );

        createRunner(
          executionPath: ticketDir.path,
          processRunner: anyProcessRunner().call,
        );
        await runner.run(['add', '--no-localize', 'd']);

        expect(Directory(path.join(ticketDir.path, 'c')).existsSync(), isTrue);
        expect(Directory(path.join(ticketDir.path, 'd')).existsSync(), isTrue);
      });

      test('clones a dependency only a ticket repo declares', () async {
        oceanRepo('tx_other');

        final ticketDir = ticket('T_CLONE');
        File(path.join(ticketDir.path, 'ticket.json'))
            .writeAsStringSync('{"issue_id": "T_CLONE"}');
        final repo = Directory(path.join(ticketDir.path, 'tx_ticket'))
          ..createSync();
        File(path.join(repo.path, 'pubspec.yaml')).writeAsStringSync(
          'name: tx_ticket\n'
          'version: 1.0.0\n'
          'dependencies:\n'
          '  tx_new_dep:\n'
          '    git:\n'
          '      url: https://github.com/some_org/tx_new_dep.git\n',
        );

        // The clone declares a dependency of its own, which is followed too.
        when(
          () => mockGitCloner.cloneRepo(
            'git@github.com:tx_new_dep/tx_new_dep.git',
            any(),
          ),
        ).thenAnswer((invocation) async {
          final target = invocation.positionalArguments[1] as String;
          File(path.join(target, 'pubspec.yaml'))
            ..createSync(recursive: true)
            ..writeAsStringSync(
              'name: tx_new_dep\n'
              'version: 1.0.0\n'
              'dependencies:\n'
              '  tx_deeper:\n'
              '    git:\n'
              '      url: https://github.com/some_org/tx_deeper.git\n',
            );
        });

        createRunner(
          executionPath: ticketDir.path,
          processRunner: anyProcessRunner().call,
        );
        await runner.run(['add', '--no-localize', 'tx_other']);

        verify(
          () => mockGitCloner.cloneRepo(
            'git@github.com:tx_new_dep/tx_new_dep.git',
            any(),
          ),
        ).called(1);
        verify(
          () => mockGitCloner.cloneRepo(
            'git@github.com:tx_deeper/tx_deeper.git',
            any(),
          ),
        ).called(1);
      });

      test('does not refresh what the ticket repos merely depend on', () async {
        oceanRepo('tx_other');
        oceanRepo('tx_tooling');

        final ticketDir = ticket('T_FRESH');
        File(path.join(ticketDir.path, 'ticket.json'))
            .writeAsStringSync('{"issue_id": "T_FRESH"}');
        final repo = Directory(path.join(ticketDir.path, 'tx_ticket'))
          ..createSync();
        File(path.join(repo.path, 'pubspec.yaml')).writeAsStringSync(
          'name: tx_ticket\nversion: 1.0.0\n'
          'dev_dependencies:\n  tx_tooling: ^1.0.0\n',
        );

        final refreshed = <String>[];
        final repoFreshness = MockRepoFreshness();
        registerFallbackValue(<Directory>[]);
        when(
          () => repoFreshness.updateAll(
            ggLog: any(named: 'ggLog'),
            directories: any(named: 'directories'),
            workspacePath: any(named: 'workspacePath'),
          ),
        ).thenAnswer((invocation) async {
          final dirs =
              invocation.namedArguments[#directories] as Iterable<Directory>;
          refreshed.addAll(dirs.map((d) => path.basename(d.path)));
        });

        runner = CommandRunner<void>('test', 'Test for AddCommand')
          ..addCommand(
            AddCommand(
              ggLog: ggLog,
              gitCloner: mockGitCloner,
              processRunner: anyProcessRunner().call,
              oceanWorkspacePath: oceanWorkspacePath,
              executionPath: ticketDir.path,
              repoFreshness: repoFreshness,
              defaultBranch: fakeDefaultBranch(),
            ),
          );
        await runner.run(['add', '--no-localize', 'tx_other']);

        // Only the requested repo's closure is fetched, not the ticket's.
        expect(refreshed, contains('tx_other'));
        expect(refreshed, isNot(contains('tx_tooling')));
      });
    });

    test('logs when dependency graph building fails and continues', () async {
      const repoName = 'graphFailRepo';
      final repoDir = Directory(path.join(oceanWorkspacePath, repoName))
        ..createSync(recursive: true);
      File(path.join(repoDir.path, 'file.txt')).writeAsStringSync('x');

      final ticketDir = Directory(
        path.join(tempDir.path, ggMultiLegacyTicketFolder, 'T-DFG'),
      )..createSync(recursive: true);

      final mockGraph = MockGraph();
      when(
        () => mockGraph.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          packageDirs: any(named: 'packageDirs'),
        ),
      ).thenThrow(Exception('graph error'));

      final mockProc = MockProcessRunner();
      when(
        () => mockProc(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, '', ''));

      final cmdRunner = CommandRunner<void>('test', 'Add with graph mock')
        ..addCommand(
          AddCommand(
            ggLog: ggLog,
            gitCloner: mockGitCloner,
            oceanWorkspacePath: oceanWorkspacePath,
            executionPath: ticketDir.path,
            processRunner: mockProc.call,
            graph: mockGraph,
            defaultBranch: fakeDefaultBranch(),
          ),
        );

      await cmdRunner.run(['add', repoName]);

      expect(
        logMessages.any(
          (m) => m.contains(
            'Failed to build dependency graph: Exception: graph error',
          ),
        ),
        isTrue,
      );
    });

    group('dart pub upgrade in localization', () {
      test(
        'executes dart pub upgrade after localize and logs success',
        () async {
          const repoName = 'upgradeRepo';
          final repoDir = Directory(path.join(oceanWorkspacePath, repoName))
            ..createSync(recursive: true);
          File(path.join(repoDir.path, 'pubspec.yaml'))
              .writeAsStringSync('name: $repoName');

          final ticketDir = Directory(
            path.join(tempDir.path, ggMultiLegacyTicketFolder, 'T-UPG'),
          )..createSync(recursive: true);

          final mockSorted = MockSortedProcessingList();
          when(
            () => mockSorted.get(
              directory: any(named: 'directory'),
              ggLog: any(named: 'ggLog'),
            ),
          ).thenAnswer(
            (_) async => [
              Node(
                name: repoName,
                directory: Directory(path.join(ticketDir.path, repoName)),
                manifest: DartPackageManifest(pubspec: Pubspec(repoName)),
              ),
            ],
          );

          final mockLoc = MockLocalizeRefs();
          when(
            () => mockLoc.get(
              directory: any(named: 'directory'),
              ggLog: any(named: 'ggLog'),
            ),
          ).thenAnswer((_) async {});

          final mockProc = MockProcessRunner();
          when(
            () => mockProc(
              'git',
              any(),
              workingDirectory: any(named: 'workingDirectory'),
              runInShell: true,
            ),
          ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
          when(
            () => mockProc(
              'dart',
              ['pub', 'get'],
              workingDirectory: any(named: 'workingDirectory'),
              runInShell: true,
            ),
          ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
          when(
            () => mockProc(
              'dart',
              ['pub', 'upgrade'],
              workingDirectory: any(named: 'workingDirectory'),
              runInShell: true,
            ),
          ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));

          final mockDoCommit = MockGgSystemCommit();
          when(
            () => mockDoCommit.commit(
              directory: any(named: 'directory'),
              ggLog: any(named: 'ggLog'),
              message: any(named: 'message'),
              paths: any(named: 'paths'),
              includeUntracked: any(named: 'includeUntracked'),
              ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
              userCommitMessage: any(named: 'userCommitMessage'),
              stateKey: any(named: 'stateKey'),
              keepForeignChanges: any(named: 'keepForeignChanges'),
            ),
          ).thenAnswer(
            (_) async => const gg.GgSystemCommitResult(
              userCommitCreated: false,
              systemCommitCreated: true,
              ggOwnedPaths: ['pubspec_overrides.yaml'],
              foreignPaths: [],
            ),
          );

          when(
            () => mockProc(
              'git',
              ['status', '--porcelain', '--untracked-files=no'],
              workingDirectory: any(named: 'workingDirectory'),
              runInShell: true,
            ),
          ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
          createRunner(
            executionPath: ticketDir.path,
            processRunner: mockProc.call,
            systemCommit: mockDoCommit,
            sortedProcessingList: mockSorted,
            localizeRefs: mockLoc,
          );

          await runner.run(['add', '--verbose', repoName]);

          expect(
            logMessages.any(
              (m) => m.contains('Executed dart pub upgrade in $repoName.'),
            ),
            isTrue,
          );
        },
      );

      test('logs error and aborts when dart pub upgrade '
          'fails in localization', () async {
        const repoName = 'upgradeFailRepo';
        final repoDir = Directory(path.join(oceanWorkspacePath, repoName))
          ..createSync(recursive: true);
        File(path.join(repoDir.path, 'pubspec.yaml'))
            .writeAsStringSync('name: $repoName');

        final ticketDir = Directory(
          path.join(tempDir.path, ggMultiLegacyTicketFolder, 'T-UPG-FAIL'),
        )..createSync(recursive: true);

        final mockSorted = MockSortedProcessingList();
        when(
          () => mockSorted.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer(
          (_) async => [
            Node(
              name: repoName,
              directory: Directory(path.join(ticketDir.path, repoName)),
              manifest: DartPackageManifest(pubspec: Pubspec(repoName)),
            ),
          ],
        );

        final mockLoc = MockLocalizeRefs();
        when(
          () => mockLoc.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        final mockProc = MockProcessRunner();
        when(
          () => mockProc(
            'git',
            any(),
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
        when(
          () => mockProc(
            'dart',
            ['pub', 'get'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
        when(
          () => mockProc(
            'dart',
            ['pub', 'upgrade'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 1, '', 'Upgrade error'));

        final mockDoCommit = MockGgSystemCommit();
        when(
          () => mockDoCommit.commit(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            paths: any(named: 'paths'),
            includeUntracked: any(named: 'includeUntracked'),
            ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
            userCommitMessage: any(named: 'userCommitMessage'),
            stateKey: any(named: 'stateKey'),
            keepForeignChanges: any(named: 'keepForeignChanges'),
          ),
        ).thenAnswer(
          (_) async => const gg.GgSystemCommitResult(
            userCommitCreated: false,
            systemCommitCreated: true,
            ggOwnedPaths: ['pubspec_overrides.yaml'],
            foreignPaths: [],
          ),
        );

        when(
          () => mockProc(
            'git',
            ['status', '--porcelain', '--untracked-files=no'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
        createRunner(
          executionPath: ticketDir.path,
          processRunner: mockProc.call,
          systemCommit: mockDoCommit,
          sortedProcessingList: mockSorted,
          localizeRefs: mockLoc,
        );

        await runner.run(['add', '--verbose', repoName]);

        expect(
          logMessages.any(
            (m) => m.contains(
              'Failed to execute dart pub upgrade '
              'in $repoName: Upgrade error',
            ),
          ),
          isTrue,
        );
      });
    });

    test(
      'removes obsolete gg git hooks from ticket repositories after add',
      () async {
        const repoName = 'hooksRepo';

        final oceanRepoDir = Directory(path.join(oceanWorkspacePath, repoName))
          ..createSync(recursive: true);
        File(path.join(oceanRepoDir.path, 'pubspec.yaml'))
            .writeAsStringSync('name: $repoName');
        Directory(path.join(oceanRepoDir.path, '.git')).createSync();

        // An older gg version installed a pre-push hook here. The copy into
        // the ticket carries it along, so `do add` must clean it up.
        Directory(path.join(oceanRepoDir.path, '.git', 'hooks'))
            .createSync(recursive: true);
        File(path.join(oceanRepoDir.path, '.git', 'hooks', 'pre-push'))
            .writeAsStringSync(
              '#!/bin/sh\nset -e\n\ndart run .gg/verify_push.dart',
            );
        Directory(path.join(oceanRepoDir.path, '.gg'))
            .createSync(recursive: true);
        File(path.join(oceanRepoDir.path, '.gg', 'verify_push.dart'))
            .writeAsStringSync('void main() {}');

        // A hook gg never generated. It proves the copy really carries
        // .git/hooks over, so the missing pre-push below is a deletion and
        // not just a file that never arrived.
        File(path.join(oceanRepoDir.path, '.git', 'hooks', 'pre-commit'))
            .writeAsStringSync('#!/bin/sh\necho "my own hook"');

        final ticketDir = Directory(
          path.join(tempDir.path, ggMultiLegacyTicketFolder, 'TICKET-HOOKS'),
        )..createSync(recursive: true);

        final mockProc = MockProcessRunner();
        when(
          () => mockProc(
            'git',
            ['fetch'],
            workingDirectory: oceanRepoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProc(
            'git',
            ['remote', 'set-head', 'origin', '--auto'],
            workingDirectory: oceanRepoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProc(
            'git',
            ['reset', '--hard', 'origin/main'],
            workingDirectory: oceanRepoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProc(
            'git',
            ['tag', '-l'],
            workingDirectory: oceanRepoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
        when(
          () => mockProc(
            'git',
            ['fetch', '--tags'],
            workingDirectory: oceanRepoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProc(
            'git',
            ['fetch', '--prune', '--tags'],
            workingDirectory: oceanRepoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProc(
            'dart',
            ['pub', 'get'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProc(
            'dart',
            ['pub', 'upgrade'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProc(
            'git',
            ['config', 'merge.ours.driver', 'true'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: any(named: 'runInShell'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

        final mockDoCommit = MockGgSystemCommit();
        when(
          () => mockDoCommit.commit(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            paths: any(named: 'paths'),
            includeUntracked: any(named: 'includeUntracked'),
            ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
            userCommitMessage: any(named: 'userCommitMessage'),
            stateKey: any(named: 'stateKey'),
            keepForeignChanges: any(named: 'keepForeignChanges'),
          ),
        ).thenAnswer(
          (_) async => const gg.GgSystemCommitResult(
            userCommitCreated: false,
            systemCommitCreated: true,
            ggOwnedPaths: ['pubspec_overrides.yaml'],
            foreignPaths: [],
          ),
        );

        when(
          () => mockProc(
            'git',
            ['status', '--porcelain', '--untracked-files=no'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
        createRunner(
          executionPath: ticketDir.path,
          processRunner: mockProc.call,
          systemCommit: mockDoCommit,
        );

        await runner.run(['add', repoName]);

        final ticketRepoDir = Directory(path.join(ticketDir.path, repoName));
        final prePushHook = File(
          path.join(ticketRepoDir.path, '.git', 'hooks', 'pre-push'),
        );
        final verifyPushScript = File(
          path.join(ticketRepoDir.path, '.gg', 'verify_push.dart'),
        );

        expect(prePushHook.existsSync(), isFalse);
        expect(verifyPushScript.existsSync(), isFalse);

        // The user's own hook is untouched.
        expect(
          File(path.join(ticketRepoDir.path, '.git', 'hooks', 'pre-commit'))
              .existsSync(),
          isTrue,
        );
      },
    );

    test('invokes BackupPublishTo before localize for each repo', () async {
      const repoName = 'backupRepo';
      final repoDir = Directory(path.join(oceanWorkspacePath, repoName))
        ..createSync(recursive: true);
      File(path.join(repoDir.path, 'pubspec.yaml'))
          .writeAsStringSync('name: $repoName');

      final ticketDir = Directory(
        path.join(tempDir.path, ggMultiLegacyTicketFolder, 'T-BACKUP'),
      )..createSync(recursive: true);

      final mockSorted = MockSortedProcessingList();
      when(
        () => mockSorted.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer(
        (_) async => [
          Node(
            name: repoName,
            directory: Directory(path.join(ticketDir.path, repoName)),
            manifest: DartPackageManifest(pubspec: Pubspec(repoName)),
          ),
        ],
      );

      final mockLoc = MockLocalizeRefs();
      final mockBackup = MockBackupPublishTo();

      final order = <String>[];
      when(
        () => mockBackup.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {
        order.add('backup');
      });
      when(
        () => mockLoc.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {
        order.add('localize');
      });

      final mockProc = MockProcessRunner();
      when(
        () => mockProc(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

      final mockDoCommit = MockGgSystemCommit();
      when(
        () => mockDoCommit.commit(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          paths: any(named: 'paths'),
          includeUntracked: any(named: 'includeUntracked'),
          ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
          userCommitMessage: any(named: 'userCommitMessage'),
          stateKey: any(named: 'stateKey'),
          keepForeignChanges: any(named: 'keepForeignChanges'),
        ),
      ).thenAnswer(
        (_) async => const gg.GgSystemCommitResult(
          userCommitCreated: false,
          systemCommitCreated: true,
          ggOwnedPaths: ['pubspec_overrides.yaml'],
          foreignPaths: [],
        ),
      );

      when(
        () => mockProc(
          'git',
          ['status', '--porcelain', '--untracked-files=no'],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      createRunner(
        executionPath: ticketDir.path,
        processRunner: mockProc.call,
        systemCommit: mockDoCommit,
        sortedProcessingList: mockSorted,
        localizeRefs: mockLoc,
        backupPublishTo: mockBackup,
      );

      await runner.run(['add', repoName]);

      expect(order, ['backup', 'localize']);
    });

    group('organization folders', () {
      // A process runner that answers every git/dart call successfully.
      MockProcessRunner anyProcessRunner() {
        final mockProc = MockProcessRunner();
        when(
          () => mockProc(
            any(),
            any(),
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: any(named: 'runInShell'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
        return mockProc;
      }

      MockGgSystemCommit anyDoCommit() {
        final mockDoCommit = MockGgSystemCommit();
        when(
          () => mockDoCommit.commit(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            paths: any(named: 'paths'),
            includeUntracked: any(named: 'includeUntracked'),
            ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
            userCommitMessage: any(named: 'userCommitMessage'),
            stateKey: any(named: 'stateKey'),
            keepForeignChanges: any(named: 'keepForeignChanges'),
          ),
        ).thenAnswer(
          (_) async => const gg.GgSystemCommitResult(
            userCommitCreated: false,
            systemCommitCreated: true,
            ggOwnedPaths: ['pubspec_overrides.yaml'],
            foreignPaths: [],
          ),
        );
        return mockDoCommit;
      }

      // Creates an ocean repo at [relativePath] carrying a git remote.
      Directory makeMasterRepo(String relativePath, String remoteUrl) {
        final dir = Directory(path.join(oceanWorkspacePath, relativePath))
          ..createSync(recursive: true);
        File(path.join(dir.path, 'pubspec.yaml')).writeAsStringSync(
          'name: ${path.basename(relativePath)}\nversion: 1.0.0\n',
        );
        final gitDir = Directory(path.join(dir.path, '.git'))..createSync();
        File(path.join(gitDir.path, 'config'))
            .writeAsStringSync('[remote "origin"]\n\turl = $remoteUrl\n');
        return dir;
      }

      Directory makeTicketDir(String name) =>
          Directory(path.join(tempDir.path, ggMultiLegacyTicketFolder, name))
            ..createSync(recursive: true);

      test('copies an ocean org repo flat into the ticket', () async {
        makeMasterRepo(
          path.join('ggsuite', 'gg_foo'),
          'https://github.com/ggsuite/gg_foo.git',
        );
        final ticketDir = makeTicketDir('TICKET_ORG');

        createRunner(
          executionPath: ticketDir.path,
          processRunner: anyProcessRunner().call,
          systemCommit: anyDoCommit(),
        );

        await runner.run(['add', 'gg_foo']);

        // The ocean groups the repo by organization; the ticket does not.
        expect(
          Directory(path.join(ticketDir.path, 'gg_foo')).existsSync(),
          isTrue,
        );
        expect(
          Directory(path.join(ticketDir.path, 'ggsuite')).existsSync(),
          isFalse,
        );

        final ws = jsonDecode(
          File(path.join(ticketDir.path, 'TICKET_ORG.code-workspace'))
              .readAsStringSync(),
        ) as Map<String, dynamic>;
        final paths = (ws['folders'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((f) => f['path'] as String)
            .toSet();
        expect(paths, <String>{'gg_foo'});
      });

      test('gives the second repo of a name its own org folder', () async {
        // Two organizations own a `gg_foo` — the only case a ticket still
        // needs an organization folder for.
        makeMasterRepo(
          path.join('ggsuite', 'gg_foo'),
          'https://github.com/ggsuite/gg_foo.git',
        );
        makeMasterRepo(
          path.join('other', 'gg_foo'),
          'https://github.com/other/gg_foo.git',
        );
        final ticketDir = makeTicketDir('TICKET_CLASH');

        createRunner(
          executionPath: ticketDir.path,
          processRunner: anyProcessRunner().call,
          systemCommit: anyDoCommit(),
        );

        // Localizing is off: two Dart packages of one name in a ticket are
        // a conflict of their own, and this test is about the folders.
        // The first one lands flat ...
        await runner.run([
          'add',
          '--no-localize',
          'https://github.com/ggsuite/gg_foo.git',
        ]);
        expect(
          File(path.join(ticketDir.path, 'gg_foo', 'pubspec.yaml'))
              .existsSync(),
          isTrue,
        );

        // ... the second one, whose flat spot is taken, into its org folder.
        await runner.run([
          'add',
          '--no-localize',
          'https://github.com/other/gg_foo.git',
        ]);
        expect(
          File(path.join(ticketDir.path, 'other', 'gg_foo', 'pubspec.yaml'))
              .existsSync(),
          isTrue,
        );
      });

      test('does not copy a ticket repo a second time', () async {
        makeMasterRepo(
          path.join('ggsuite', 'gg_foo'),
          'https://github.com/ggsuite/gg_foo.git',
        );
        final ticketDir = makeTicketDir('TICKET_TWICE');

        createRunner(
          executionPath: ticketDir.path,
          processRunner: anyProcessRunner().call,
          systemCommit: anyDoCommit(),
        );

        await runner.run(['add', 'gg_foo']);
        File(path.join(ticketDir.path, 'gg_foo', 'marker.txt'))
            .writeAsStringSync('keep');
        await runner.run(['add', 'gg_foo']);

        // The repo is recognized by its remote, so it is left alone instead
        // of being copied into an organization folder beside itself.
        expect(
          File(path.join(ticketDir.path, 'gg_foo', 'marker.txt'))
              .readAsStringSync(),
          'keep',
        );
        expect(
          Directory(path.join(ticketDir.path, 'ggsuite')).existsSync(),
          isFalse,
        );
      });

      test('moves the repos of an old ocean into their org folders', () async {
        makeMasterRepo('gg_foo', 'https://github.com/ggsuite/gg_foo.git');
        final ticketDir = makeTicketDir('TICKET_MIGRATE');

        createRunner(
          executionPath: ticketDir.path,
          processRunner: anyProcessRunner().call,
          systemCommit: anyDoCommit(),
        );

        await runner.run(['add', 'gg_foo']);

        expect(
          Directory(path.join(oceanWorkspacePath, 'ggsuite', 'gg_foo'))
              .existsSync(),
          isTrue,
        );
        expect(
          Directory(path.join(oceanWorkspacePath, 'gg_foo')).existsSync(),
          isFalse,
        );
        expect(
          Directory(path.join(ticketDir.path, 'gg_foo')).existsSync(),
          isTrue,
        );
        expect(logMessages, contains('✓ ggsuite/gg_foo'));
      });

      test('moves the repos of an old ticket out of their org '
          'folders', () async {
        makeMasterRepo(
          path.join('ggsuite', 'gg_foo'),
          'https://github.com/ggsuite/gg_foo.git',
        );
        final ticketDir = makeTicketDir('TICKET_OLD');

        // The ticket still holds its copy in an organization folder.
        final oldCopy = Directory(
          path.join(ticketDir.path, 'ggsuite', 'gg_foo'),
        )..createSync(recursive: true);
        File(path.join(oldCopy.path, 'pubspec.yaml'))
            .writeAsStringSync('name: gg_foo\nversion: 1.0.0\n');
        final gitDir = Directory(path.join(oldCopy.path, '.git'))..createSync();
        File(path.join(gitDir.path, 'config')).writeAsStringSync(
          '[remote "origin"]\n\turl = https://github.com/ggsuite/gg_foo.git\n',
        );
        File(path.join(oldCopy.path, 'marker.txt')).writeAsStringSync('keep');

        createRunner(
          executionPath: ticketDir.path,
          processRunner: anyProcessRunner().call,
          systemCommit: anyDoCommit(),
        );

        await runner.run(['add', 'gg_foo']);

        // The existing copy is moved, not replaced by a fresh one.
        expect(
          File(path.join(ticketDir.path, 'gg_foo', 'marker.txt'))
              .readAsStringSync(),
          'keep',
        );
        // The organization folder that lost its last repo is gone.
        expect(
          Directory(path.join(ticketDir.path, 'ggsuite')).existsSync(),
          isFalse,
        );
      });

      test('does not clone a repo again that sits in an org folder', () async {
        makeMasterRepo(
          path.join('ggsuite', 'gg_foo'),
          'https://github.com/ggsuite/gg_foo.git',
        );

        createRunner(
          executionPath: Directory.systemTemp.createTempSync('no_ticket_').path,
        );

        await runner.run(['add', 'https://github.com/ggsuite/gg_foo.git']);

        verifyNever(() => mockGitCloner.cloneRepo(any(), any()));
        expect(logMessages, contains('✓ gg_foo (already added).'));
      });
    });

    group('--localize, --org and --all', () {
      late MockLocalizeRefs mockLoc;
      late MockGgSystemCommit mockDoCommit;
      late MockProcessRunner mockProc;

      setUp(() {
        mockProc = MockProcessRunner();
        when(
          () => mockProc(
            any(),
            any(),
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: any(named: 'runInShell'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

        mockLoc = MockLocalizeRefs();
        when(
          () => mockLoc.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        mockDoCommit = MockGgSystemCommit();
        when(
          () => mockDoCommit.commit(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            paths: any(named: 'paths'),
            includeUntracked: any(named: 'includeUntracked'),
            ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
            userCommitMessage: any(named: 'userCommitMessage'),
            stateKey: any(named: 'stateKey'),
            keepForeignChanges: any(named: 'keepForeignChanges'),
          ),
        ).thenAnswer(
          (_) async => const gg.GgSystemCommitResult(
            userCommitCreated: false,
            systemCommitCreated: true,
            ggOwnedPaths: ['pubspec_overrides.yaml'],
            foreignPaths: [],
          ),
        );
      });

      // Creates an ocean repo at [relativePath] carrying a git remote.
      void makeMasterRepo(String relativePath, String remoteUrl) {
        final dir = Directory(path.join(oceanWorkspacePath, relativePath))
          ..createSync(recursive: true);
        File(path.join(dir.path, 'pubspec.yaml')).writeAsStringSync(
          'name: ${path.basename(relativePath)}\nversion: 1.0.0\n',
        );
        final gitDir = Directory(path.join(dir.path, '.git'))..createSync();
        File(path.join(gitDir.path, 'config'))
            .writeAsStringSync('[remote "origin"]\n\turl = $remoteUrl\n');
      }

      Directory makeTicketDir(String name) =>
          Directory(path.join(tempDir.path, ggMultiLegacyTicketFolder, name))
            ..createSync(recursive: true);

      void createTicketRunner(Directory ticketDir) => createRunner(
        executionPath: ticketDir.path,
        processRunner: mockProc.call,
        systemCommit: mockDoCommit,
        localizeRefs: mockLoc,
      );

      // Creates orgA/repo1, orgA/repo2 and orgB/repo3 in the ocean.
      void makeTwoOrgs() {
        makeMasterRepo(
          path.join('orgA', 'repo1'),
          'https://github.com/orgA/repo1.git',
        );
        makeMasterRepo(
          path.join('orgA', 'repo2'),
          'https://github.com/orgA/repo2.git',
        );
        makeMasterRepo(
          path.join('orgB', 'repo3'),
          'https://github.com/orgB/repo3.git',
        );
      }

      // The repos of the ticket, addressed the way the ticket holds them —
      // flat, so plain names.
      Set<String> ticketRepoPaths(Directory ticketDir) => <String>{
        for (final repo in RepoFolderResolver.repoDirs(ticketDir.path))
          RepoFolderResolver.relativePath(
            workspacePath: ticketDir.path,
            repoDir: repo,
          ),
      };

      test('localizes the refs by default', () async {
        makeMasterRepo(
          path.join('ggsuite', 'gg_foo'),
          'https://github.com/ggsuite/gg_foo.git',
        );
        final ticketDir = makeTicketDir('TICKET_LOC');
        createTicketRunner(ticketDir);

        await runner.run(['add', 'gg_foo']);

        verify(
          () => mockLoc.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).called(1);
      });

      test('--no-localize copies the repos but keeps the refs', () async {
        makeMasterRepo(
          path.join('ggsuite', 'gg_foo'),
          'https://github.com/ggsuite/gg_foo.git',
        );
        final ticketDir = makeTicketDir('TICKET_NOLOC');
        createTicketRunner(ticketDir);

        await runner.run(['add', '--no-localize', 'gg_foo']);

        // The repo is copied ...
        expect(
          Directory(path.join(ticketDir.path, 'gg_foo')).existsSync(),
          isTrue,
        );

        // ... but nothing touched its references.
        verifyNever(
          () => mockLoc.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        );
        verifyNever(
          () => mockDoCommit.commit(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            paths: any(named: 'paths'),
            includeUntracked: any(named: 'includeUntracked'),
            ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
            userCommitMessage: any(named: 'userCommitMessage'),
            stateKey: any(named: 'stateKey'),
            keepForeignChanges: any(named: 'keepForeignChanges'),
          ),
        );

        // The ticket description stays current nevertheless.
        expect(
          File(path.join(ticketDir.path, 'ticket.json')).existsSync(),
          isTrue,
        );
        expect(
          logMessages,
          contains('Skip localizing references (--no-localize).'),
        );
      });

      test('--org adds all repos of that organization folder', () async {
        makeTwoOrgs();
        final ticketDir = makeTicketDir('TICKET_ORG_OPT');
        createTicketRunner(ticketDir);

        await runner.run(['add', '--org', 'orgA']);

        expect(ticketRepoPaths(ticketDir), {'repo1', 'repo2'});
      });

      test('--org is repeatable', () async {
        makeTwoOrgs();
        final ticketDir = makeTicketDir('TICKET_ORG_MULTI');
        createTicketRunner(ticketDir);

        await runner.run(['add', '--org', 'orgA', '--org', 'orgB']);

        expect(ticketRepoPaths(ticketDir), {'repo1', 'repo2', 'repo3'});
      });

      test('--org warns about an unknown organization', () async {
        makeTwoOrgs();
        final ticketDir = makeTicketDir('TICKET_ORG_UNKNOWN');
        createTicketRunner(ticketDir);

        await runner.run(['add', '--org', 'orgX']);

        expect(
          logMessages,
          contains(
            'No repositories found for organization orgX '
            'in the ocean.',
          ),
        );
        expect(logMessages, contains('No repositories to add.'));
        expect(ticketRepoPaths(ticketDir), isEmpty);
      });

      test('--all adds all repos of the ocean', () async {
        makeTwoOrgs();
        final ticketDir = makeTicketDir('TICKET_ALL');
        createTicketRunner(ticketDir);

        await runner.run(['add', '--all']);

        expect(ticketRepoPaths(ticketDir), {'repo1', 'repo2', 'repo3'});
      });

      test('--all and --org are refused outside a ticket', () async {
        createRunner(
          executionPath: Directory.systemTemp.createTempSync('no_ticket_').path,
        );

        await expectLater(
          () => runner.run(['add', '--all']),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              contains('can only be used from inside a ticket workspace'),
            ),
          ),
        );

        await expectLater(
          () => runner.run(['add', '--org', 'orgA']),
          throwsA(isA<UsageException>()),
        );
      });

      test('still requires a target without --all and --org', () async {
        createRunner(
          executionPath: Directory.systemTemp.createTempSync('no_ticket_').path,
        );

        await expectLater(
          () => runner.run(['add']),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              'Missing target parameter.',
            ),
          ),
        );
      });
    });

    group('default branch', () {
      late Directory ticketDir;

      /// Runs git with [args] in [dir] and fails the test when it fails.
      Future<String> git(Directory dir, List<String> args) async {
        final result = await Process.run('git', [
          '-c',
          'user.name=test',
          '-c',
          'user.email=test@example.com',
          ...args,
        ], workingDirectory: dir.path);
        if (result.exitCode != 0) {
          fail('git ${args.join(' ')} failed: ${result.stderr}');
        }
        return (result.stdout as String).trim();
      }

      gg.GgSystemCommit anyDoCommit() {
        final mock = MockGgSystemCommit();
        when(
          () => mock.commit(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            paths: any(named: 'paths'),
            includeUntracked: any(named: 'includeUntracked'),
            ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
            userCommitMessage: any(named: 'userCommitMessage'),
            stateKey: any(named: 'stateKey'),
            keepForeignChanges: any(named: 'keepForeignChanges'),
          ),
        ).thenAnswer(
          (_) async => const gg.GgSystemCommitResult(
            userCommitCreated: false,
            systemCommitCreated: true,
            ggOwnedPaths: ['pubspec_overrides.yaml'],
            foreignPaths: [],
          ),
        );
        return mock;
      }

      setUp(() {
        ticketDir = Directory(
          path.join(tempDir.path, ggMultiLegacyTicketFolder, 'TICKET_DEFAULT'),
        )..createSync(recursive: true);
      });

      test('resets the ocean copy to origin/develop when that is the '
          'default branch and no main exists', () async {
        const repoName = 'devRepo';

        // The remote: a bare repository whose HEAD is develop. There is no
        // main and no master anywhere.
        final src = Directory(path.join(tempDir.path, 'dev_src'))..createSync();
        await git(src, ['init', '-b', 'develop']);
        File(path.join(src.path, 'README.md')).writeAsStringSync('one\n');
        await git(src, ['add', '.']);
        await git(src, ['commit', '-m', 'first']);
        final originDir = Directory(path.join(tempDir.path, 'dev_origin.git'));
        await git(tempDir, ['clone', '--bare', src.path, originDir.path]);
        await git(src, ['remote', 'add', 'origin', originDir.path]);

        // The ocean copy was built with git init + remote add, so it has no
        // origin/HEAD at all — the state that made the old origin/main reset
        // fail with "unknown revision".
        final oceanRepoDir = Directory(path.join(oceanWorkspacePath, repoName))
          ..createSync(recursive: true);
        await git(oceanRepoDir, ['init', '-b', 'develop']);
        await git(oceanRepoDir, ['remote', 'add', 'origin', originDir.path]);
        await git(oceanRepoDir, ['fetch', 'origin']);
        await git(oceanRepoDir, ['reset', '--hard', 'origin/develop']);
        final headBefore = await git(oceanRepoDir, ['rev-parse', 'HEAD']);

        // The remote moves on after the ocean copy was made.
        File(path.join(src.path, 'second.txt')).writeAsStringSync('two\n');
        await git(src, ['add', '.']);
        await git(src, ['commit', '-m', 'second']);
        await git(src, ['push', 'origin', 'develop']);
        final remoteHead = await git(src, ['rev-parse', 'HEAD']);
        expect(remoteHead, isNot(headBefore));

        createRunner(
          executionPath: ticketDir.path,
          systemCommit: anyDoCommit(),
          defaultBranch: DefaultBranch(ggLog: ggLog),
        );

        await runner.run(['add', '--verbose', repoName]);

        // origin/HEAD was refreshed from the remote ...
        expect(
          await git(oceanRepoDir, ['symbolic-ref', 'refs/remotes/origin/HEAD']),
          'refs/remotes/origin/develop',
        );
        expect(
          logMessages,
          contains('Refreshed origin/HEAD in $repoName in ocean.'),
        );

        // ... and the ocean copy was reset to origin/develop, not origin/main.
        expect(
          logMessages,
          contains(
            'Executed git reset --hard origin/develop in $repoName in ocean.',
          ),
        );
        expect(logMessages.any((m) => m.contains('origin/main')), isFalse);
        expect(await git(oceanRepoDir, ['rev-parse', 'HEAD']), remoteHead);

        // The ticket got the fresh state.
        final copied = Directory(path.join(ticketDir.path, repoName));
        expect(copied.existsSync(), isTrue);
        expect(File(path.join(copied.path, 'second.txt')).existsSync(), isTrue);
      });

      test('throws when the ocean repo has no default branch at all', () async {
        const repoName = 'noDefaultRepo';
        final oceanRepoDir = Directory(path.join(oceanWorkspacePath, repoName))
          ..createSync(recursive: true);
        File(path.join(oceanRepoDir.path, 'file.txt')).writeAsStringSync('x');

        final mockProc = MockProcessRunner();
        when(
          () => mockProc(
            any(),
            any(),
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: any(named: 'runInShell'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

        createRunner(
          executionPath: ticketDir.path,
          processRunner: mockProc.call,
          defaultBranch: fakeDefaultBranch(''),
        );

        await expectLater(
          () async => runner.run(['add', '--verbose', repoName]),
          throwsA(
            isA<Exception>().having(
              (e) => rmControls(e.toString()),
              'message',
              contains(
                'Repository $repoName in the ocean has no default branch',
              ),
            ),
          ),
        );

        // Nothing was reset and nothing was copied.
        verifyNever(
          () => mockProc(
            'git',
            any(that: contains('reset')),
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: any(named: 'runInShell'),
          ),
        );
        expect(
          Directory(path.join(ticketDir.path, repoName)).existsSync(),
          isFalse,
        );
      });

      test('only warns when origin/HEAD cannot be refreshed', () async {
        const repoName = 'offlineRepo';
        final oceanRepoDir = Directory(path.join(oceanWorkspacePath, repoName))
          ..createSync(recursive: true);
        File(path.join(oceanRepoDir.path, 'file.txt')).writeAsStringSync('x');

        // Every git call succeeds except the one asking the remote for its
        // default branch — what an offline machine sees.
        Future<ProcessResult> offlineSetHead(
          String executable,
          List<String> arguments, {
          String? workingDirectory,
          Map<String, String>? environment,
          bool runInShell = true,
        }) async => arguments.join(' ') == 'remote set-head origin --auto'
            ? ProcessResult(0, 128, '', 'fatal: offline')
            : ProcessResult(0, 0, '', '');

        createRunner(
          executionPath: ticketDir.path,
          processRunner: offlineSetHead,
          systemCommit: anyDoCommit(),
        );

        await runner.run(['add', '--verbose', repoName]);

        expect(
          logMessages,
          contains(
            'Could not refresh origin/HEAD in $repoName in ocean: '
            'fatal: offline',
          ),
        );
        expect(
          logMessages,
          contains(
            'Executed git reset --hard origin/main in $repoName in ocean.',
          ),
        );
        expect(
          Directory(path.join(ticketDir.path, repoName)).existsSync(),
          isTrue,
        );
      });
    });
  });
}
