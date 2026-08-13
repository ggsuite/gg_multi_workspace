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

class MockUnlocalizeRefs extends Mock implements ChangeRefsToPubDev {}

class MockGraph extends Mock implements Graph {}

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
      ChangeRefsToPubDev? unlocalizeRefs,
      ChangeRefsToLocal? localizeRefs,
      BackupPublishTo? backupPublishTo,
      Graph? graph,
      FetchRepoUrl? fetchRepoUrl,
    }) {
      final execPath = Directory.systemTemp.createTempSync('exec_path_').path;
      runner = CommandRunner<void>('test', 'Test for AddCommand');
      runner.addCommand(
        AddCommand(
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          processRunner: processRunner,
          oceanWorkspacePath: oceanWorkspacePath,
          executionPath: executionPath ?? execPath,
          systemCommit: systemCommit,
          sortedProcessingList: sortedProcessingList,
          unlocalizeRefs: unlocalizeRefs,
          localizeRefs: localizeRefs,
          backupPublishTo: backupPublishTo,
          graph: graph,
          fetchRepoUrl: fetchRepoUrl,
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
      verify(
        () => mockGitCloner.cloneRepo(
          'https://github.com/myrepo/myrepo.git',
          any(),
        ),
      ).called(1);
      expect(
        logMessages,
        anyElement(
          contains('myrepo from https://github.com/myrepo/myrepo.git'),
        ),
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
          'https://github.com/testuser/testrepo.git',
          any(),
        ),
      ).called(1);
      expect(
        logMessages,
        anyElement(
          contains('testrepo from https://github.com/testuser/testrepo.git'),
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
          'https://github.com/ggsuite/gg_multi.git',
          any(),
        ),
      ).called(1);
      expect(
        logMessages,
        anyElement(
          contains('gg_multi from https://github.com/ggsuite/gg_multi.git'),
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
          oceanWorkspacePath: oceanWorkspacePath,
          // Without an execution path the command would resolve the ticket
          // of the checkout the tests run in and modify it.
          executionPath: tempDir.path,
          systemCommit: mockDoCommit,
        ),
      );
      const orgUrl = 'https://github.com/myorganization';
      await orgRunner.run(['add', orgUrl]);
      verify(
        () => mockGitCloner.cloneRepo(
          'https://github.com/myorganization/repo1.git',
          any(),
        ),
      ).called(1);
      verify(
        () => mockGitCloner.cloneRepo(
          'https://github.com/myorganization/repo2.git',
          any(),
        ),
      ).called(1);
      expect(
        logMessages,
        anyElement(
          contains('repo1 from https://github.com/myorganization/repo1.git'),
        ),
      );
      expect(
        logMessages,
        anyElement(
          contains('repo2 from https://github.com/myorganization/repo2.git'),
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

    test('copies repo into ticket workspace and relocalizes ticket '
        '(two passes)', () async {
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

      verify(
        () => mockDoCommit.commit(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: '#gg: changed references to path',
          paths: any(named: 'paths'),
          includeUntracked: any(named: 'includeUntracked'),
          ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
          userCommitMessage: any(named: 'userCommitMessage'),
          // Localizing rewrites the manifests, so the recorded »everything
          // is committed« hash has to be taken anew — otherwise the next
          // command in the ticket sees a repo that looks uncommitted.
          stateKey: gg.GgState.doCommitKey,
        ),
      ).called(greaterThanOrEqualTo(1));

      expect(
        logMessages.any(
          (m) => m.contains('Re-localized all repositories in ticket'),
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

      // Org fallback: `https://github.com/<dep>/<dep>.git`.
      verify(
        () => mockGitCloner.cloneRepo(
          'https://github.com/$gitDepName/$gitDepName.git',
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
        ),
      ).thenAnswer(
        (_) async => const gg.GgSystemCommitResult(
          userCommitCreated: false,
          systemCommitCreated: true,
          ggOwnedPaths: ['pubspec_overrides.yaml'],
          foreignPaths: [],
        ),
      );

      const repoUrl = '${orgUrl}tx_known_org_dep.git';
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

      verify(() => mockGitCloner.cloneRepo(repoUrl, any())).called(1);
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
        'relocalization', () async {
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

        // npm install runs twice: after copy and after relocalize.
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
        // origin/main first, so the report can rule out a stale copy.
        expect(log, contains('on the state of origin/main'));
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
          // After relocalize: dart pub upgrade also runs.
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

    test('commit failures are logged and aborts immediately', () async {
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
        ),
      ).thenThrow(Exception('commit error'));

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
          () => mockGitCloner.cloneRepo(
            'https://github.com/repoA/repoA.git',
            any(),
          ),
        ).called(1);
        verify(
          () => mockGitCloner.cloneRepo(
            'https://github.com/repoB/repoB.git',
            any(),
          ),
        ).called(1);
        expect(
          logMessages,
          anyElement(contains('repoA from https://github.com/repoA/repoA.git')),
        );
        expect(
          logMessages,
          anyElement(contains('repoB from https://github.com/repoB/repoB.git')),
        );
      },
    );

    test('relocalization aborts and logs when localize fails', () async {
      const repoName = 'localizeFailRepo';
      final repoDir = Directory(path.join(oceanWorkspacePath, repoName))
        ..createSync(recursive: true);
      File(path.join(repoDir.path, 'pubspec.yaml'))
          .writeAsStringSync('name: $repoName');

      final ticketDir = Directory(
        path.join(tempDir.path, ggMultiLegacyTicketFolder, 'TICKET-LOCFAIL'),
      )..createSync(recursive: true);

      final mockSorted = MockSortedProcessingList();
      final mockUnloc = MockUnlocalizeRefs();
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
        () => mockUnloc.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});
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
        unlocalizeRefs: mockUnloc,
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
            (m) => m.contains('Re-localized all repositories in ticket TXYZ'),
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
              'Re-localized all repositories in ticket TXYZ_EXISTING',
            ),
          ),
          isTrue,
        );
      },
    );

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

    group('dart pub upgrade in relocalization', () {
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

          final mockUnloc = MockUnlocalizeRefs();
          final mockLoc = MockLocalizeRefs();
          when(
            () => mockUnloc.get(
              directory: any(named: 'directory'),
              ggLog: any(named: 'ggLog'),
            ),
          ).thenAnswer((_) async {});
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
            unlocalizeRefs: mockUnloc,
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
          'fails in relocalization', () async {
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

        final mockUnloc = MockUnlocalizeRefs();
        final mockLoc = MockLocalizeRefs();
        when(
          () => mockUnloc.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});
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
          unlocalizeRefs: mockUnloc,
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

    test('unlocalizes when backup file exists in ticket repository', () async {
      const repoName = 'backupRepo';
      final oceanRepoDir = Directory(path.join(oceanWorkspacePath, repoName))
        ..createSync(recursive: true);

      File(path.join(oceanRepoDir.path, 'pubspec.yaml'))
          .writeAsStringSync('name: $repoName');

      File(path.join(oceanRepoDir.path, '.gg_localize_refs_backup.json'))
          .writeAsStringSync('{}');

      final ticketDir = Directory(
        path.join(tempDir.path, ggMultiLegacyTicketFolder, 'TICKET-BACKUP'),
      )..createSync(recursive: true);

      final mockSorted = MockSortedProcessingList();
      final mockUnloc = MockUnlocalizeRefs();
      final mockLoc = MockLocalizeRefs();
      final mockDoCommit = MockGgSystemCommit();
      final mockProc = MockProcessRunner();

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

      when(
        () => mockSorted.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((invocation) async {
        final dir = invocation.namedArguments[#directory] as Directory;
        final ticketRepoDir = Directory(path.join(dir.path, repoName));
        return [
          Node(
            name: repoName,
            directory: ticketRepoDir,
            manifest: DartPackageManifest(pubspec: Pubspec(repoName)),
          ),
        ];
      });

      when(
        () => mockUnloc.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockLoc.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

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
        unlocalizeRefs: mockUnloc,
        localizeRefs: mockLoc,
      );

      await runner.run(['add', repoName]);

      final ticketRepoBackup = File(
        path.join(ticketDir.path, repoName, '.gg_localize_refs_backup.json'),
      );
      expect(ticketRepoBackup.existsSync(), isTrue);

      verify(
        () => mockUnloc.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).called(1);
    });

    test('logs error and aborts when unlocalize fails '
        'in relocalization pass', () async {
      const repoName = 'unlocFailRepo';
      final oceanRepoDir = Directory(path.join(oceanWorkspacePath, repoName))
        ..createSync(recursive: true);

      File(path.join(oceanRepoDir.path, 'pubspec.yaml'))
          .writeAsStringSync('name: $repoName');

      File(path.join(oceanRepoDir.path, '.gg_localize_refs_backup.json'))
          .writeAsStringSync('{}');

      final ticketDir = Directory(
        path.join(tempDir.path, ggMultiLegacyTicketFolder, 'TICKET-UNLOC-FAIL'),
      )..createSync(recursive: true);

      final mockSorted = MockSortedProcessingList();
      final mockUnloc = MockUnlocalizeRefs();
      final mockLoc = MockLocalizeRefs();
      final mockDoCommit = MockGgSystemCommit();
      final mockProc = MockProcessRunner();

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

      when(
        () => mockSorted.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((invocation) async {
        final dir = invocation.namedArguments[#directory] as Directory;
        final ticketRepoDir = Directory(path.join(dir.path, repoName));
        return [
          Node(
            name: repoName,
            directory: ticketRepoDir,
            manifest: DartPackageManifest(pubspec: Pubspec(repoName)),
          ),
        ];
      });

      when(
        () => mockUnloc.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenThrow(Exception('unloc failed'));

      when(
        () => mockLoc.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

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
        unlocalizeRefs: mockUnloc,
        localizeRefs: mockLoc,
      );

      await expectLater(
        () async => await runner.run(['add', '--verbose', repoName]),
        throwsA(isA<Exception>()),
      );

      expect(
        logMessages.any(
          (m) => m.contains(
            'Failed to unlocalize refs for $repoName: '
            'Exception: unloc failed',
          ),
        ),
        isTrue,
      );
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

      final mockUnloc = MockUnlocalizeRefs();
      final mockLoc = MockLocalizeRefs();
      final mockBackup = MockBackupPublishTo();

      final order = <String>[];
      when(
        () => mockUnloc.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockBackup.exec(
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
        unlocalizeRefs: mockUnloc,
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
      late MockUnlocalizeRefs mockUnloc;
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

        mockUnloc = MockUnlocalizeRefs();
        when(
          () => mockUnloc.get(
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
        unlocalizeRefs: mockUnloc,
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
          () => mockUnloc.get(
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
  });
}
