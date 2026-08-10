// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_multi_workspace/src/backend/git_handler.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

// A mock class for the ProcessRunner function.
class MockProcessRunner extends Mock {
  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool? runInShell,
  });
}

void main() {
  // Group all tests for GitCloner
  group('GitHandler', () {
    late Directory tempDir;
    late GitHandler gitHandler;
    late MockProcessRunner mockProcessRunner;

    // Setup before each test
    setUp(() async {
      // Create a temporary directory for testing
      tempDir = await Directory.systemTemp.createTemp('git_cloner_test');
      // Initialize the mock process runner
      mockProcessRunner = MockProcessRunner();
      // Create a GitCloner instance with the injected mock process runner
      gitHandler = GitHandler(processRunner: mockProcessRunner.call);
    });

    // Cleanup the temporary directory after each test
    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('cloneRepo', () {
      test(
        'successfully clones a repository when process returns exit code 0',
        () async {
          // Arrange
          const repoUrl = 'https://github.com/example/repo.git';
          // Create a target directory path inside the temporary directory
          final targetDirectory = path.join(tempDir.path, 'cloned_repo');

          // Ensure that the parent directory does not yet exist
          final parentDir = Directory(targetDirectory).parent;
          if (await parentDir.exists()) {
            await parentDir.delete(recursive: true);
          }
          expect(await parentDir.exists(), isFalse);

          // Stub the mock process runner to return a successful ProcessResult
          when(() => mockProcessRunner('git', any())).thenAnswer(
            (_) async => ProcessResult(123, 0, 'Cloned successfully', ''),
          );

          // Act
          await gitHandler.cloneRepo(repoUrl, targetDirectory);

          // Assert
          // Verify that the process runner was called with correct arguments
          verify(
            () => mockProcessRunner(
              'git',
              any(that: equals(['clone', repoUrl, targetDirectory])),
            ),
          ).called(1);

          // Check that the parent directory now exists
          expect(await parentDir.exists(), isTrue);
        },
      );

      test('throws an exception when the clone process fails', () async {
        // Arrange
        const repoUrl = 'https://github.com/example/failure.git';
        final targetDirectory = path.join(tempDir.path, 'failed_clone');

        // Stub the mock process runner to return a failing ProcessResult
        when(() => mockProcessRunner('git', any())).thenAnswer(
          (_) async => ProcessResult(456, 1, '', 'Error cloning repository'),
        );

        // Act & Assert
        expect(
          () async => await gitHandler.cloneRepo(repoUrl, targetDirectory),
          throwsA(
            predicate(
              (e) =>
                  e is Exception &&
                  rmControls(e.toString()) ==
                      'Exception: Failed to clone repo from $repoUrl: '
                          'Error cloning repository',
            ),
          ),
        );

        // Verify that the process runner was called
        verify(
          () => mockProcessRunner(
            'git',
            any(that: equals(['clone', repoUrl, targetDirectory])),
          ),
        ).called(1);
      });

      test('removes the folders it created when the clone fails', () async {
        // Arrange: the org folder does not exist yet, so cloneRepo has to
        // create it — a failing clone must not leave it behind.
        const repoUrl = 'https://github.com/unknownOrg/unknown.git';
        final orgDir = Directory(path.join(tempDir.path, 'unknownOrg'));
        final targetDirectory = path.join(orgDir.path, 'unknown');
        expect(orgDir.existsSync(), isFalse);

        when(() => mockProcessRunner('git', any())).thenAnswer(
          (_) async => ProcessResult(456, 1, '', 'repository not found'),
        );

        // Act
        await expectLater(
          gitHandler.cloneRepo(repoUrl, targetDirectory),
          throwsA(isA<Exception>()),
        );

        // Assert
        expect(Directory(targetDirectory).existsSync(), isFalse);
        expect(orgDir.existsSync(), isFalse);
      });

      test('removes a whole tree of folders it created', () async {
        // Arrange: neither the workspace nor the org folder exist, so
        // cloneRepo walks up to the first existing ancestor and creates
        // several levels at once. A failing clone must remove all of them.
        const repoUrl = 'https://github.com/unknownOrg/unknown.git';
        final workspaceDir = Directory(
          path.join(tempDir.path, 'new_workspace'),
        );
        final orgDir = Directory(path.join(workspaceDir.path, 'unknownOrg'));
        final targetDirectory = path.join(orgDir.path, 'unknown');
        expect(workspaceDir.existsSync(), isFalse);

        when(() => mockProcessRunner('git', any())).thenAnswer(
          (_) async => ProcessResult(456, 1, '', 'repository not found'),
        );

        // Act
        await expectLater(
          gitHandler.cloneRepo(repoUrl, targetDirectory),
          throwsA(isA<Exception>()),
        );

        // Assert — the outermost created folder is gone with everything
        // in it, while the pre-existing temp folder survives.
        expect(workspaceDir.existsSync(), isFalse);
        expect(tempDir.existsSync(), isTrue);
      });

      test('keeps an existing org folder that holds other repos', () async {
        // Arrange: the org folder existed before and holds another repo, so
        // a failing clone must leave it untouched.
        const repoUrl = 'https://github.com/knownOrg/unknown.git';
        final orgDir = Directory(path.join(tempDir.path, 'knownOrg'));
        final otherRepo = Directory(path.join(orgDir.path, 'other_repo'));
        otherRepo.createSync(recursive: true);
        final targetDirectory = path.join(orgDir.path, 'unknown');

        when(() => mockProcessRunner('git', any())).thenAnswer(
          (_) async => ProcessResult(456, 1, '', 'repository not found'),
        );

        // Act
        await expectLater(
          gitHandler.cloneRepo(repoUrl, targetDirectory),
          throwsA(isA<Exception>()),
        );

        // Assert
        expect(Directory(targetDirectory).existsSync(), isFalse);
        expect(orgDir.existsSync(), isTrue);
        expect(otherRepo.existsSync(), isTrue);
      });

      test(
        'ensures parent directory is created if it does not exist',
        () async {
          // Arrange
          const repoUrl = 'https://github.com/example/repo.git';
          // Choosing a target directory in a nested non-existent structure
          final targetDirectory = path.join(
            tempDir.path,
            'nonexistent',
            'cloned_repo',
          );
          final parentDir = Directory(targetDirectory).parent;

          // Make sure the parent directory does not exist
          if (await parentDir.exists()) {
            await parentDir.delete(recursive: true);
          }
          expect(await parentDir.exists(), isFalse);

          // Stub the process runner to return success
          when(() => mockProcessRunner('git', any())).thenAnswer(
            (_) async => ProcessResult(789, 0, 'Cloned successfully', ''),
          );

          // Act
          await gitHandler.cloneRepo(repoUrl, targetDirectory);

          // Assert
          // The parent directory should have been created
          expect(await parentDir.exists(), isTrue);

          // Verify that the process runner was called correctly
          verify(
            () => mockProcessRunner(
              'git',
              any(that: equals(['clone', repoUrl, targetDirectory])),
            ),
          ).called(1);
        },
      );
    });
  });

  group('GitHandler.checkoutBranch', () {
    late MockProcessRunner mockProcessRunner;
    late GitHandler gitHandler;

    setUp(() {
      mockProcessRunner = MockProcessRunner();
      gitHandler = GitHandler(processRunner: mockProcessRunner.call);
    });

    test('successful branch checkout', () async {
      when(
        () => mockProcessRunner('git', [
          '-C',
          'repoDir',
          'checkout',
          '-b',
          'feature',
        ]),
      ).thenAnswer((_) async => ProcessResult(1, 0, '', ''));

      await gitHandler.checkoutBranch('feature', 'repoDir');

      verify(
        () => mockProcessRunner('git', [
          '-C',
          'repoDir',
          'checkout',
          '-b',
          'feature',
        ]),
      ).called(1);
    });

    group('remoteExists', () {
      test('is true when git can list the remote', () async {
        when(
          () => mockProcessRunner('git', [
            'ls-remote',
            'https://github.com/org/repo.git',
          ]),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'hash\tHEAD', ''));

        expect(
          await gitHandler.remoteExists('https://github.com/org/repo.git'),
          isTrue,
        );
      });

      test('is false when the remote is not reachable', () async {
        when(
          () => mockProcessRunner('git', ['ls-remote', 'https://x/none.git']),
        ).thenAnswer((_) async => ProcessResult(0, 128, '', 'not found'));

        expect(await gitHandler.remoteExists('https://x/none.git'), isFalse);
      });

      test('is false when git cannot be run at all', () async {
        // A missing git binary must not look like a missing repository.
        when(
          () => mockProcessRunner('git', ['ls-remote', 'https://x/none.git']),
        ).thenThrow(const ProcessException('git', <String>[]));

        expect(await gitHandler.remoteExists('https://x/none.git'), isFalse);
      });
    });

    test('throws when checkout branch fails', () async {
      when(
        () => mockProcessRunner('git', [
          '-C',
          'repoDir',
          'checkout',
          '-b',
          'bug',
        ]),
      ).thenAnswer((_) async => ProcessResult(2, 1, '', 'err message'));

      expect(
        () => gitHandler.checkoutBranch('bug', 'repoDir'),
        throwsA(
          predicate(
            (e) =>
                e is Exception &&
                rmControls(e.toString()) ==
                    'Exception: Failed to checkout branch bug in repoDir: '
                        'err message',
          ),
        ),
      );
    });
  });
}
