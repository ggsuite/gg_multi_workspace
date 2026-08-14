// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_multi_workspace/src/backend/add_repository_helper.dart';
import 'package:gg_multi_workspace/src/backend/git_handler.dart';
import 'package:gg_multi_core/gg_multi_core.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

// Create a mock for GitCloner
class MockGitCloner extends Mock implements GitHandler {}

class MockGitHubPlatform extends Mock implements GitHubPlatform {}

class MockAzurePlatform extends Mock implements AzureDevOpsPlatform {}

// Dummy implementation for repoFetcher in tests
typedef RepoFetcher = Future<http.Response> Function(Uri uri);

void main() {
  // Common variables used in tests
  late List<String> logs;
  late Directory tempWorkspace;
  late String workspacePath;

  // Setup a simple ggLog function that appends messages to logs list
  void ggLog(String message) {
    logs.add(rmControls(message));
  }

  setUp(() {
    logs = [];
    // Use a temporary directory for the workspace
    tempWorkspace = Directory.systemTemp.createTempSync('dummy_workspace_test');
    workspacePath = tempWorkspace.path;
  });

  tearDown(() {
    if (tempWorkspace.existsSync()) {
      tempWorkspace.deleteSync(recursive: true);
    }
  });

  group('addRepositoryHelper', () {
    group('HTTP target', () {
      test('Processes repository URL and cleans trailing #', () async {
        // This test covers the branch when
        // targetArg starts with http and is a repository URL
        const targetArg = 'http://github.com/user/repo#';
        final mockGitCloner = MockGitCloner();
        // Stub cloneRepo to complete normally
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          workspacePath: workspacePath,
          force: false,
        );

        // The URL should have the trailing '#' removed and appended with .git
        const expectedRepoUrl = 'http://github.com/user/repo.git';
        // The repo lands in the folder of the organization of its URL.
        final expectedDestination = path.join(workspacePath, 'user', 'repo');

        // Verify cloneRepo was called with correct parameters
        verify(
          () => mockGitCloner.cloneRepo(expectedRepoUrl, expectedDestination),
        ).called(1);

        // Verify ggLog contains the correct success message
        expect(logs, anyElement(contains('repo from $expectedRepoUrl')));
      });

      test('Clones only the named repo of a /orgs/<org>/<repo> url', () async {
        // The org page with a repo appended is a web path, not a clone url —
        // and it must add that one repo, not the whole organization.
        const targetArg = 'https://github.com/orgs/ggsuite/gg_dna';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          workspacePath: workspacePath,
          force: false,
        );

        verify(
          () => mockGitCloner.cloneRepo(
            'https://github.com/ggsuite/gg_dna.git',
            path.join(workspacePath, 'ggsuite', 'gg_dna'),
          ),
        ).called(1);
      });

      test('Processes repository URL that already ends with .git', () async {
        const targetArg = 'https://github.com/user/repo.git';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          workspacePath: workspacePath,
          force: false,
        );

        final expectedDestination = path.join(workspacePath, 'user', 'repo');
        verify(() => mockGitCloner.cloneRepo(targetArg, expectedDestination))
            .called(1);
        expect(logs, anyElement(contains('repo from $targetArg')));
      });

      test('Processes organization URL and clones multiple repos', () async {
        // Test for the organization URL branch
        // where the URL has less than 2 path segments.
        const targetArg = 'http://github.com/myorg';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        // Build a fake repo list response with two repositories
        final repoList = <Repository>[
          const Repository(
            name: 'repo1',
            httpsUrl: 'https://github.com/myorg/repo1.git',
          ),
          const Repository(
            name: 'repo2',
            httpsUrl: 'https://github.com/myorg/repo2.git',
          ),
        ];

        final mockGitHubPlatform = MockGitHubPlatform();
        when(
          () => mockGitHubPlatform.fetchOrgRepos(
            any(),
            client: any(named: 'client'),
          ),
        ).thenAnswer((_) async => repoList);

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          gitHubPlatform: mockGitHubPlatform,
          workspacePath: workspacePath,
          force: false,
        );

        // Verify cloneRepo called for each repository
        for (final repo in repoList) {
          final repoName = repo.name;
          final cloneUrl = repo.httpsUrl;
          final destination = path.join(workspacePath, 'myorg', repoName);
          verify(() => mockGitCloner.cloneRepo(cloneUrl, destination))
              .called(1);
          expect(logs, anyElement(contains('$repoName from $cloneUrl')));
        }
      });

      test('Logs one header and exactly one success line per repo', () async {
        // Repos of an organization are cloned in parallel. The output must
        // therefore be a single header plus one line per repo - a
        // progress-then-done printer would interleave into duplicates.
        const targetArg = 'http://github.com/myorg';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        final repoList = <Repository>[
          const Repository(
            name: 'repo1',
            httpsUrl: 'https://github.com/myorg/repo1.git',
          ),
          const Repository(
            name: 'repo2',
            httpsUrl: 'https://github.com/myorg/repo2.git',
          ),
        ];

        final mockGitHubPlatform = MockGitHubPlatform();
        when(
          () => mockGitHubPlatform.fetchOrgRepos(
            any(),
            client: any(named: 'client'),
          ),
        ).thenAnswer((_) async => repoList);

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          gitHubPlatform: mockGitHubPlatform,
          workspacePath: workspacePath,
          force: false,
        );

        expect(logs, [
          'Cloning repos ...',
          '✓ repo1 from https://github.com/myorg/repo1.git',
          '✓ repo2 from https://github.com/myorg/repo2.git',
        ]);
      });

      test('Treats /orgs/<org> URL as organization and clones repos', () async {
        // The GitHub browser URL for an organization overview page carries an
        // extra `orgs` path segment; it must still be recognised as an org.
        const targetArg = 'https://github.com/orgs/myorg';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        final repoList = <Repository>[
          const Repository(
            name: 'repo1',
            httpsUrl: 'https://github.com/myorg/repo1.git',
            sshUrl: 'git@github.com:myorg/repo1.git',
          ),
        ];

        final mockGitHubPlatform = MockGitHubPlatform();
        when(
          () => mockGitHubPlatform.fetchOrgRepos(
            'myorg',
            client: any(named: 'client'),
          ),
        ).thenAnswer((_) async => repoList);

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          gitHubPlatform: mockGitHubPlatform,
          workspacePath: workspacePath,
          force: false,
        );

        // Verify it queried the correct org and cloned via the ssh url.
        verify(
          () => mockGitHubPlatform.fetchOrgRepos(
            'myorg',
            client: any(named: 'client'),
          ),
        ).called(1);
        verify(
          () => mockGitCloner.cloneRepo(
            'git@github.com:myorg/repo1.git',
            path.join(workspacePath, 'myorg', 'repo1'),
          ),
        ).called(1);
      });

      test('Processes organization URL with empty repo list', () async {
        // Test organization branch when no repositories are found
        const targetArg = 'http://github.com/myorg';
        final mockGitCloner = MockGitCloner();
        // Since no repos found, cloneRepo should not be called
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        final mockGitHubPlatform = MockGitHubPlatform();
        when(
          () => mockGitHubPlatform.fetchOrgRepos(
            any(),
            client: any(named: 'client'),
          ),
        ).thenAnswer((_) async => <Repository>[]);

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          gitHubPlatform: mockGitHubPlatform,
          workspacePath: workspacePath,
          force: false,
        );

        // Expect ggLog to log that no repositories were found
        expect(logs, contains('No repositories found for organization myorg'));

        // Verify no calls to cloneRepo
        verifyNever(() => mockGitCloner.cloneRepo(any(), any()));
      });

      test('Rethrows when fetching organization repos fails', () async {
        const targetArg = 'http://github.com/myorg';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        final mockGitHubPlatform = MockGitHubPlatform();
        when(
          () => mockGitHubPlatform.fetchOrgRepos(
            any(),
            client: any(named: 'client'),
          ),
        ).thenThrow(
          Exception('Failed to fetch repositories for organization myorg'),
        );

        expect(
          () async => await addRepositoryHelper(
            targetArg: targetArg,
            ggLog: ggLog,
            gitCloner: mockGitCloner,
            gitHubPlatform: mockGitHubPlatform,
            workspacePath: workspacePath,
            force: false,
          ),
          throwsA(
            predicate(
              (e) => rmC(
                e.toString(),
              ).contains('Failed to fetch repositories for organization myorg'),
            ),
          ),
        );
      });

      test('Handles gh not installed for GitHub organization URL', () async {
        const targetArg = 'https://github.com/orgs/myorg';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        final mockGitHubPlatform = MockGitHubPlatform();
        when(
          () => mockGitHubPlatform.fetchOrgRepos(
            any(),
            client: any(named: 'client'),
          ),
        ).thenThrow(
          Exception(
            'Bitte installiere die GitHub CLI und melde dich an: \n'
            '    winget install --exact --id GitHub.cli \n'
            '    gh auth login',
          ),
        );

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          gitHubPlatform: mockGitHubPlatform,
          workspacePath: workspacePath,
          force: false,
        );

        expect(
          logs,
          contains(
            'Bitte installiere die GitHub CLI und melde dich an: \n'
            '    winget install --exact --id GitHub.cli \n'
            '    gh auth login',
          ),
        );
        verifyNever(() => mockGitCloner.cloneRepo(any(), any()));
      });

      test('Processes Azure organization URL with project', () async {
        const targetArg = 'https://ssh.dev.azure.com/v3/myorg/myproj';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        final repoList = <Repository>[
          const Repository(
            name: 'repo1',
            httpsUrl: 'https://dev.azure.com/myorg/myproj/repo1.git',
          ),
          const Repository(
            name: 'repo2',
            httpsUrl: 'https://dev.azure.com/myorg/myproj/repo2.git',
          ),
        ];

        final mockAzurePlatform = MockAzurePlatform();
        when(
          () => mockAzurePlatform.fetchOrgRepos(
            'myorg',
            project: 'myproj',
            client: any(named: 'client'),
          ),
        ).thenAnswer((_) async => repoList);

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          azureDevOpsPlatform: mockAzurePlatform,
          workspacePath: workspacePath,
          force: false,
        );

        for (final repo in repoList) {
          final repoName = repo.name;
          final cloneUrl = repo.httpsUrl;
          // On Azure DevOps the repo names are scoped to the project, so the
          // project is the folder that keeps them apart.
          final destination = path.join(workspacePath, 'myproj', repoName);
          verify(() => mockGitCloner.cloneRepo(cloneUrl, destination))
              .called(1);
          expect(logs, anyElement(contains('$repoName from $cloneUrl')));
        }
      });

      test('Processes Azure organization URL with empty repo list', () async {
        const targetArg = 'https://ssh.dev.azure.com/v3/myorg/myproj';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        final mockAzurePlatform = MockAzurePlatform();
        when(
          () => mockAzurePlatform.fetchOrgRepos(
            'myorg',
            project: 'myproj',
            client: any(named: 'client'),
          ),
        ).thenAnswer((_) async => <Repository>[]);

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          azureDevOpsPlatform: mockAzurePlatform,
          workspacePath: workspacePath,
          force: false,
        );

        expect(
          logs,
          contains(
            'No repositories found for organization myorg and project myproj',
          ),
        );
        verifyNever(() => mockGitCloner.cloneRepo(any(), any()));
      });

      test('Skips Azure organization if no project provided', () async {
        const targetArg = 'https://ssh.dev.azure.com/v3/myorg';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        final mockAzurePlatform = MockAzurePlatform();
        when(
          () => mockAzurePlatform.fetchOrgRepos(
            any(),
            project: any(named: 'project'),
            client: any(named: 'client'),
          ),
        ).thenThrow(ArgumentError('Project required'));

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          azureDevOpsPlatform: mockAzurePlatform,
          workspacePath: workspacePath,
          force: false,
        );

        // Since no project, it should treat as repo URL, not org
        verify(() => mockGitCloner.cloneRepo(any(), any())).called(1);
      });

      test('Handles az not installed for Azure organization URL', () async {
        const targetArg = 'https://ssh.dev.azure.com/v3/myorg/myproj';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        final mockAzurePlatform = MockAzurePlatform();
        when(
          () => mockAzurePlatform.fetchOrgRepos(
            'myorg',
            project: 'myproj',
            client: any(named: 'client'),
          ),
        ).thenThrow(
          Exception(
            'Bitte installiere die Azure CLI mit folgenden Befehlen: \n'
            '    winget install --exact --id Microsoft.AzureCLI \n'
            '    az extension add --name azure-devops',
          ),
        );

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          azureDevOpsPlatform: mockAzurePlatform,
          workspacePath: workspacePath,
          force: false,
        );

        expect(
          logs,
          contains(
            'Bitte installiere die Azure CLI mit folgenden Befehlen: \n'
            '    winget install --exact --id Microsoft.AzureCLI \n'
            '    az extension add --name azure-devops',
          ),
        );
        verifyNever(() => mockGitCloner.cloneRepo(any(), any()));
      });

      test(
        'Rethrows non-az-install exceptions for Azure organization',
        () async {
          const targetArg = 'https://ssh.dev.azure.com/v3/myorg/myproj';
          final mockGitCloner = MockGitCloner();
          when(() => mockGitCloner.cloneRepo(any(), any()))
              .thenAnswer((_) async {});

          final mockAzurePlatform = MockAzurePlatform();
          when(
            () => mockAzurePlatform.fetchOrgRepos(
              'myorg',
              project: 'myproj',
              client: any(named: 'client'),
            ),
          ).thenThrow(Exception('Other error'));

          await expectLater(
            () => addRepositoryHelper(
              targetArg: targetArg,
              ggLog: ggLog,
              gitCloner: mockGitCloner,
              azureDevOpsPlatform: mockAzurePlatform,
              workspacePath: workspacePath,
              force: false,
            ),
            throwsException,
          );

          expect(
            logs.any((msg) => msg.contains('Bitte installiere die Azure CLI')),
            isFalse,
          );
        },
      );
    });

    group('SSH URL target', () {
      test('Processes SSH URL correctly', () async {
        const targetArg = 'git@github.com:user/repo.git';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          workspacePath: workspacePath,
          force: false,
        );

        final expectedDestination = path.join(workspacePath, 'user', 'repo');
        verify(() => mockGitCloner.cloneRepo(targetArg, expectedDestination))
            .called(1);
        expect(logs, anyElement(contains('repo from $targetArg')));
      });
    });

    test('Processes Azure SSH URL correctly', () async {
      const targetArg =
          'git@ssh.dev.azure.com:v3/goeranhegenberg/project123/project123.git';
      final mockGitCloner = MockGitCloner();
      when(() => mockGitCloner.cloneRepo(any(), any()))
          .thenAnswer((_) async {});

      await addRepositoryHelper(
        targetArg: targetArg,
        ggLog: ggLog,
        gitCloner: mockGitCloner,
        workspacePath: workspacePath,
        force: false,
      );

      // The Azure project — here named like the repo — is the folder.
      final expectedDestination = path.join(
        workspacePath,
        'project123',
        'project123',
      );
      verify(() => mockGitCloner.cloneRepo(targetArg, expectedDestination))
          .called(1);
      expect(logs, anyElement(contains('project123 from $targetArg')));
    });

    group('Target containing "/" (non-http, non-SSH)', () {
      test('Processes target with slash correctly', () async {
        const targetArg = 'user/repo';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          workspacePath: workspacePath,
          force: false,
        );

        const expectedRepoUrl = 'https://github.com/user/repo.git';
        final expectedDestination = path.join(workspacePath, 'user', 'repo');
        verify(
          () => mockGitCloner.cloneRepo(expectedRepoUrl, expectedDestination),
        ).called(1);
        expect(logs, anyElement(contains('repo from $expectedRepoUrl')));
      });
    });

    group('Plain target', () {
      test('Processes plain target correctly', () async {
        const targetArg = 'repo';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          workspacePath: workspacePath,
          force: false,
        );

        const expectedRepoUrl = 'https://github.com/repo/repo.git';
        final expectedDestination = path.join(workspacePath, 'repo', 'repo');
        verify(
          () => mockGitCloner.cloneRepo(expectedRepoUrl, expectedDestination),
        ).called(1);
        expect(logs, anyElement(contains('repo from $expectedRepoUrl')));
      });
    });

    group('Invalid HTTP URL with empty path segments', () {
      test('Throws exception for invalid organization URL', () async {
        const targetArg = 'http://github.com';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        expect(
          () async => await addRepositoryHelper(
            targetArg: targetArg,
            ggLog: ggLog,
            gitCloner: mockGitCloner,
            workspacePath: workspacePath,
            force: false,
          ),
          throwsA(
            predicate(
              (e) => rmC(e.toString()).contains(
                'Invalid organization URL provided: http://github.com',
              ),
            ),
          ),
        );
      });

      test('Throws exception for invalid organization URL '
          'with whitespace in path', () async {
        const targetArg = 'http://github.com/ ';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        expect(
          () async => await addRepositoryHelper(
            targetArg: targetArg,
            ggLog: ggLog,
            gitCloner: mockGitCloner,
            workspacePath: workspacePath,
            force: false,
          ),
          throwsA(
            predicate(
              (e) => rmC(e.toString()).contains(
                'Invalid organization URL provided: http://github.com/',
              ),
            ),
          ),
        );
      });
    });

    group('Force flag behavior', () {
      test('force clone: deletes existing directory before cloning', () async {
        const repoName = 'repo';
        final destination = path.join(workspacePath, repoName);
        Directory(destination).createSync(recursive: true);
        File(path.join(destination, 'dummy.txt')).writeAsStringSync('data');

        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        await addRepositoryHelper(
          targetArg: repoName,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          workspacePath: workspacePath,
          force: true,
        );

        verify(
          () => mockGitCloner.cloneRepo(
            'https://github.com/repo/repo.git',
            any(),
          ),
        ).called(1);
      });

      test('non-force: logs already added if destination exists', () async {
        const repoName = 'repo';
        final destination = path.join(workspacePath, repoName);
        Directory(destination).createSync(recursive: true);
        File(path.join(destination, 'dummy.txt')).writeAsStringSync('data');

        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        await addRepositoryHelper(
          targetArg: repoName,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          workspacePath: workspacePath,
          force: false,
        );

        verifyNever(() => mockGitCloner.cloneRepo(any(), any()));
        expect(logs, contains('✓ repo (already added).'));
      });
    });

    test('uses fallback organization when primary clone fails', () async {
      // Arrange: write .organizations file in workspace
      final orgFile = File(path.join(workspacePath, '.organizations'));
      const fallbackOrgName = 'fallbackOrg';
      const fallbackOrgUrl = 'https://github.com/fallbackOrg';
      orgFile.writeAsStringSync(jsonEncode({fallbackOrgName: fallbackOrgUrl}));

      // Given a plain repo name (targetArg), the initial github URL...
      const repoName = 'test';
      const primaryUrl = 'https://github.com/$repoName/$repoName.git';
      const fallbackUrl = '$fallbackOrgUrl/$repoName.git';
      // The primary URL guesses the repo name as organization, the fallback
      // URL names the real one — each clone goes to its own org folder.
      final primaryDestination = path.join(workspacePath, repoName, repoName);
      final fallbackDestination = path.join(
        workspacePath,
        fallbackOrgName,
        repoName,
      );

      final mockGitCloner = MockGitCloner();
      // First attempt fails (default github)
      when(() => mockGitCloner.cloneRepo(primaryUrl, any()))
          .thenThrow(Exception('Primary clone failure'));
      // Second attempt (fallback) succeeds
      when(() => mockGitCloner.cloneRepo(fallbackUrl, any()))
          .thenAnswer((_) async {});

      var callbackExecuted = false;
      Future<void> onRepoAdded(String name) async {
        expect(name, equals(repoName));
        callbackExecuted = true;
      }

      // Act
      await addRepositoryHelper(
        targetArg: repoName,
        ggLog: ggLog,
        gitCloner: mockGitCloner,
        workspacePath: workspacePath,
        force: false,
        onRepoAdded: onRepoAdded,
      );

      // Assert: fallbackUrl was used
      verify(() => mockGitCloner.cloneRepo(primaryUrl, primaryDestination))
          .called(1);
      verify(() => mockGitCloner.cloneRepo(fallbackUrl, fallbackDestination))
          .called(1);
      // The repo was reported as added from the fallback URL
      expect(logs, anyElement(contains('$repoName from $fallbackUrl')));
      expect(
        callbackExecuted,
        isTrue,
        reason: 'onRepoAdded should be executed when fallback url is used.',
      );
    });

    test(
      'logs error when primary and all fallback organization clones fail',
      () async {
        // Arrange: add at least one org for fallback, all fail
        final orgFile = File(path.join(workspacePath, '.organizations'));
        const fallbackOrgName = 'fallbackOrg';
        const fallbackOrgUrl = 'https://github.com/fallbackOrg';
        orgFile.writeAsStringSync(
          jsonEncode({fallbackOrgName: fallbackOrgUrl}),
        );

        const repoName = 'fallbackRepo';
        const primaryUrl = 'https://github.com/$repoName/$repoName.git';
        const fallbackUrl = '$fallbackOrgUrl/$repoName.git';

        final mockGitCloner = MockGitCloner();
        // Both primary and fallback throw an error
        when(() => mockGitCloner.cloneRepo(primaryUrl, any()))
            .thenThrow(Exception('Primary clone fail'));
        when(() => mockGitCloner.cloneRepo(fallbackUrl, any()))
            .thenThrow(Exception('Fallback fail'));

        await expectLater(
          addRepositoryHelper(
            targetArg: repoName,
            ggLog: ggLog,
            gitCloner: mockGitCloner,
            workspacePath: workspacePath,
            force: false,
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('Repository "$repoName" was not found.'),
            ),
          ),
        );

        expect(
          logs,
          contains(
            'Failed to clone repository $repoName '
            'from any known organizations.',
          ),
        );
      },
    );

    test('logs the failure hint when the clone fails', () async {
      // Arrange: one fallback org, every clone fails
      final orgFile = File(path.join(workspacePath, '.organizations'));
      const fallbackOrgUrl = 'https://github.com/fallbackOrg';
      orgFile.writeAsStringSync(jsonEncode({'fallbackOrg': fallbackOrgUrl}));

      const repoName = 'hintRepo';

      final mockGitCloner = MockGitCloner();
      when(() => mockGitCloner.cloneRepo(any(), any()))
          .thenThrow(Exception('Clone fail'));

      // Act
      await expectLater(
        addRepositoryHelper(
          targetArg: repoName,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          workspacePath: workspacePath,
          failureHint: 'Declared in /somewhere/package.json',
        ),
        throwsA(isA<Exception>()),
      );

      // Assert
      expect(logs, contains('Declared in /somewhere/package.json'));
    });

    group('plain name owned by several organizations', () {
      const repoName = 'shared_repo';
      const urlA = 'https://github.com/orgA/$repoName.git';
      const urlB = 'https://github.com/orgB/$repoName.git';

      /// Registers [names] as known organizations of the workspace.
      void writeOrganizations(List<String> names) {
        File(path.join(workspacePath, '.organizations')).writeAsStringSync(
          jsonEncode(<String, String>{
            for (final name in names) name: 'https://github.com/$name',
          }),
        );
      }

      /// A cloner whose remotes in [owningUrls] answer, all others do not.
      MockGitCloner clonerOwning(Set<String> owningUrls) {
        final cloner = MockGitCloner();
        when(() => cloner.remoteExists(any())).thenAnswer(
          (i) async =>
              owningUrls.contains(i.positionalArguments.first as String),
        );
        when(() => cloner.cloneRepo(any(), any())).thenAnswer((_) async {});
        return cloner;
      }

      test('asks which organization is meant and clones from it', () async {
        writeOrganizations(<String>['orgA', 'orgB']);
        final mockGitCloner = clonerOwning(<String>{urlA, urlB});

        List<String>? offered;
        await addRepositoryHelper(
          targetArg: repoName,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          workspacePath: workspacePath,
          selectOrganization: (name, orgs) async {
            expect(name, repoName);
            offered = orgs.map((o) => o.name).toList();
            return orgs.last;
          },
        );

        // Both owners are offered, in the order they are registered.
        expect(offered, <String>['orgA', 'orgB']);
        verify(
          () => mockGitCloner.cloneRepo(
            urlB,
            path.join(workspacePath, 'orgB', repoName),
          ),
        ).called(1);
      });

      test('does not ask when only one organization owns the repo', () async {
        writeOrganizations(<String>['orgA', 'orgB']);
        final mockGitCloner = clonerOwning(<String>{urlB});

        var asked = false;
        await addRepositoryHelper(
          targetArg: repoName,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          workspacePath: workspacePath,
          selectOrganization: (name, orgs) async {
            asked = true;
            return orgs.first;
          },
        );

        expect(asked, isFalse);
        verify(
          () => mockGitCloner.cloneRepo(
            urlB,
            path.join(workspacePath, 'orgB', repoName),
          ),
        ).called(1);
      });

      test('stops when the selection is cancelled', () async {
        writeOrganizations(<String>['orgA', 'orgB']);
        final mockGitCloner = clonerOwning(<String>{urlA, urlB});

        await addRepositoryHelper(
          targetArg: repoName,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          workspacePath: workspacePath,
          selectOrganization: (name, orgs) async => null,
        );

        verifyNever(() => mockGitCloner.cloneRepo(any(), any()));
        expect(logs, contains('No organization chosen for $repoName.'));
      });

      test(
        'guesses and falls back when no known organization owns it',
        () async {
          writeOrganizations(<String>['orgA', 'orgB']);
          final mockGitCloner = clonerOwning(<String>{});

          await addRepositoryHelper(
            targetArg: repoName,
            ggLog: ggLog,
            gitCloner: mockGitCloner,
            workspacePath: workspacePath,
            selectOrganization: (name, orgs) async => orgs.first,
          );

          // The github.com/<name>/<name> guess is tried first.
          verify(
            () => mockGitCloner.cloneRepo(
              'https://github.com/$repoName/$repoName.git',
              path.join(workspacePath, repoName, repoName),
            ),
          ).called(1);
        },
      );

      test('asks no remote when a single organization is known', () async {
        writeOrganizations(<String>['orgA']);
        final mockGitCloner = clonerOwning(<String>{urlA});

        await addRepositoryHelper(
          targetArg: repoName,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          workspacePath: workspacePath,
        );

        verifyNever(() => mockGitCloner.remoteExists(any()));
      });

      test('asks no remote when the repo is already added', () async {
        writeOrganizations(<String>['orgA', 'orgB']);
        final mockGitCloner = clonerOwning(<String>{urlA, urlB});
        final repoDir = Directory(path.join(workspacePath, 'orgA', repoName))
          ..createSync(recursive: true);
        File(path.join(repoDir.path, 'pubspec.yaml'))
            .writeAsStringSync('name: $repoName\n');

        await addRepositoryHelper(
          targetArg: repoName,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          workspacePath: workspacePath,
        );

        verifyNever(() => mockGitCloner.remoteExists(any()));
        verifyNever(() => mockGitCloner.cloneRepo(any(), any()));
        expect(logs, contains('✓ $repoName (already added).'));
      });
    });
  });

  group('extractRepoName', () {
    test('returns repo name for SSH URL', () {
      final repoName = extractRepoName('git@github.com:owner/repo.git');
      expect(repoName, equals('repo'));
    });

    test('returns repo name for HTTP URL with .git', () {
      final repoName = extractRepoName('https://github.com/owner/repo.git');
      expect(repoName, equals('repo'));
    });

    test('returns repo name for HTTP URL without .git', () {
      final repoName = extractRepoName('https://github.com/owner/repo');
      expect(repoName, equals('repo'));
    });

    test('returns original string for invalid URL', () {
      final repoName = extractRepoName('not a url');
      expect(repoName, equals('not a url'));
    });

    test('returns repo name for Azure DevOps SSH URL with .git', () {
      final repoName = extractRepoName(
        'git@ssh.dev.azure.com:v3/goeranhegenberg/project123/project123.git',
      );
      expect(repoName, equals('project123'));
    });

    test('returns repo name for Azure DevOps SSH URL without .git', () {
      final repoName = extractRepoName(
        'git@ssh.dev.azure.com:v3/goeranhegenberg/project123/project123',
      );
      expect(repoName, equals('project123'));
    });
  });

  group('getPubspecFromWorkspace', () {
    test('returns null and logs error when pubspec.yaml parsing fails', () {
      final tempDir = Directory.systemTemp.createTempSync('pubspec_fail_test');
      final wsPath = tempDir.path;
      final projectDir = Directory(path.join(wsPath, 'bad_project'))
        ..createSync(recursive: true);
      final pubspecFile = File(path.join(projectDir.path, 'pubspec.yaml'));
      pubspecFile.writeAsStringSync('invalid content');

      final List<String> localLogs = [];
      final result = getPubspecFromWorkspace(
        targetArg: 'bad_project',
        workspacePath: wsPath,
        ggLog: (msg) => localLogs.add(msg),
      );
      expect(result, isNull);
      expect(
        localLogs.any((msg) => msg.contains('Error parsing pubspec.yaml:')),
        isTrue,
      );
      tempDir.deleteSync(recursive: true);
    });

    test('returns null and logs message when pubspec.yaml not found', () {
      final tempDir = Directory.systemTemp.createTempSync(
        'nosuch_project_test',
      );
      final wsPath = tempDir.path;
      final List<String> localLogs = [];
      final result = getPubspecFromWorkspace(
        targetArg: 'nosuch_project',
        workspacePath: wsPath,
        ggLog: (msg) => localLogs.add(msg),
      );
      expect(result, isNull);
      expect(
        localLogs.first,
        contains(
          'pubspec.yaml not found in project nosuch_project in workspace',
        ),
      );
      tempDir.deleteSync(recursive: true);
    });
  });

  test(
    'calls onRepoAdded callback when repo already exists and is non-empty',
    () async {
      // Arrange
      const repoName = 'existing_repo';
      final destination = path.join(workspacePath, repoName);
      final repoDir = Directory(destination)..createSync(recursive: true);
      File(path.join(repoDir.path, 'dummy.txt')).writeAsStringSync('data');

      final mockGitCloner = MockGitCloner();
      // cloneRepo should NOT be called because repo already present
      when(() => mockGitCloner.cloneRepo(any(), any()))
          .thenAnswer((_) async {});

      var callbackExecuted = false;
      Future<void> onRepoAdded(String name) async {
        expect(name, equals(repoName));
        callbackExecuted = true;
      }

      // Act
      await addRepositoryHelper(
        targetArg: repoName,
        ggLog: ggLog,
        gitCloner: mockGitCloner,
        workspacePath: workspacePath,
        force: false,
        onRepoAdded: onRepoAdded,
      );

      // Assert
      expect(
        callbackExecuted,
        isTrue,
        reason: 'onRepoAdded should be executed when repo already exists.',
      );
      expect(logs, contains('✓ $repoName (already added).'));
      verifyNever(() => mockGitCloner.cloneRepo(any(), any()));
    },
  );

  test('calls onRepoAdded even when repo is freshly cloned', () async {
    // Arrange
    const repoName = 'fresh_repo';
    final mockGitCloner = MockGitCloner();
    when(() => mockGitCloner.cloneRepo(any(), any())).thenAnswer((_) async {});
    bool callbackExecuted = false;
    Future<void> callback(String name) async {
      expect(name, repoName);
      callbackExecuted = true;
    }

    // Act
    await addRepositoryHelper(
      targetArg: repoName,
      ggLog: ggLog,
      gitCloner: mockGitCloner,
      workspacePath: workspacePath,
      force: true,
      onRepoAdded: callback,
    );

    // Assert
    expect(callbackExecuted, isTrue);
    verify(
      () => mockGitCloner.cloneRepo(
        'https://github.com/fresh_repo/fresh_repo.git',
        any(),
      ),
    ).called(1);
    expect(
      logs,
      anyElement(
        contains(
          'fresh_repo from '
          'https://github.com/fresh_repo/fresh_repo.git',
        ),
      ),
    );
  });

  group('a clone of a repository that is already there', () {
    /// Writes a package into [dir] that publishes as `ggsuite/dna_base`.
    void writeDnaBase(Directory dir) {
      dir.createSync(recursive: true);
      File(path.join(dir.path, 'pubspec.yaml')).writeAsStringSync(
        'name: dna_base\nversion: 1.0.0\n'
        'repository: https://github.com/ggsuite/dna_base.git\n',
      );
    }

    /// A cloner that produces such a package wherever it is told to.
    MockGitCloner clonerWritingDnaBase() {
      final cloner = MockGitCloner();
      when(() => cloner.cloneRepo(any(), any())).thenAnswer((invocation) async {
        writeDnaBase(Directory(invocation.positionalArguments[1] as String));
      });
      return cloner;
    }

    test('is dropped again and the existing one is used', () async {
      // GitHub keeps redirecting `base_dna`, the former name of `dna_base`,
      // so cloning it succeeds and yields a second checkout of a repository
      // the ocean already holds.
      writeDnaBase(Directory(path.join(workspacePath, 'ggsuite', 'dna_base')));

      String? addedRepo;
      await addRepositoryHelper(
        targetArg: 'https://github.com/ggsuite/base_dna.git',
        ggLog: ggLog,
        gitCloner: clonerWritingDnaBase(),
        workspacePath: workspacePath,
        onRepoAdded: (name) async => addedRepo = name,
      );

      expect(
        Directory(path.join(workspacePath, 'ggsuite', 'base_dna')).existsSync(),
        isFalse,
      );
      expect(
        Directory(path.join(workspacePath, 'ggsuite', 'dna_base')).existsSync(),
        isTrue,
      );

      // Everything after this works with the checkout that stays.
      expect(addedRepo, 'dna_base');
      expect(
        logs,
        anyElement(contains('base_dna is dna_base under a former name')),
      );
    });

    test('drops the organization folder it was alone in', () async {
      writeDnaBase(Directory(path.join(workspacePath, 'ggsuite', 'dna_base')));

      await addRepositoryHelper(
        targetArg: 'https://github.com/former/base_dna.git',
        ggLog: ggLog,
        gitCloner: clonerWritingDnaBase(),
        workspacePath: workspacePath,
      );

      expect(
        Directory(path.join(workspacePath, 'former')).existsSync(),
        isFalse,
      );
    });

    test('is kept when no other checkout declares that repository', () async {
      await addRepositoryHelper(
        targetArg: 'https://github.com/ggsuite/dna_base.git',
        ggLog: ggLog,
        gitCloner: clonerWritingDnaBase(),
        workspacePath: workspacePath,
      );

      expect(
        Directory(path.join(workspacePath, 'ggsuite', 'dna_base')).existsSync(),
        isTrue,
      );
      expect(logs, anyElement(contains('dna_base from')));
    });
  });
}
