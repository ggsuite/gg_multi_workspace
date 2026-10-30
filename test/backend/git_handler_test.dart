// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';
import 'dart:io';

import 'package:gg_git/gg_git.dart';
import 'package:gg_one/gg_one.dart' show GgPrompts;

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

      test('retries a clone the remote dropped', () async {
        const repoUrl = 'https://github.com/example/repo.git';
        final targetDirectory = path.join(tempDir.path, 'cloned_repo');
        var calls = 0;
        when(
          () => mockProcessRunner('git', ['clone', repoUrl, targetDirectory]),
        ).thenAnswer(
          (_) async => ++calls == 1
              ? ProcessResult(
                  0,
                  128,
                  '',
                  'Connection to github.com closed by remote host.',
                )
              : ProcessResult(0, 0, '', ''),
        );

        // No ggLog given: the notice of the retry goes nowhere.
        await GitHandler(
          processRunner: mockProcessRunner.call,
          gitRetry: GitRetry.example,
        ).cloneRepo(repoUrl, targetDirectory);

        expect(calls, 2);
      });

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

      test('is true after retrying a lookup the remote dropped', () async {
        const repoUrl = 'https://github.com/org/repo.git';
        final messages = <String>[];
        var calls = 0;
        when(() => mockProcessRunner('git', ['ls-remote', repoUrl])).thenAnswer(
          (_) async => ++calls == 1
              ? ProcessResult(
                  0,
                  128,
                  '',
                  'kex_exchange_identification: '
                      'Connection closed by remote host',
                )
              : ProcessResult(0, 0, 'hash\tHEAD', ''),
        );

        final handler = GitHandler(
          processRunner: mockProcessRunner.call,
          ggLog: messages.add,
          gitRetry: GitRetry.example,
        );

        expect(await handler.remoteExists(repoUrl), isTrue);
        expect(calls, 2);
        expect(
          messages.join('\n'),
          contains('git ls-remote $repoUrl failed with a transient'),
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

  group('GitHandler cleanup after a failed clone', () {
    late Directory tempDir;
    late MockProcessRunner mockProcessRunner;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('git_handler_cleanup');
      mockProcessRunner = MockProcessRunner();
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('leaves the folder of a clone running next to it alone', () async {
      // Arrange: the org folder is new. While this clone fails, a second
      // clone fills its own folder in the same org folder.
      const repoUrl = 'https://github.com/org/failing.git';
      final orgDir = Directory(path.join(tempDir.path, 'org'));
      final targetDirectory = path.join(orgDir.path, 'failing');
      final pack = Directory(
        path.join(orgDir.path, 'other', '.git', 'objects', 'pack'),
      );
      when(() => mockProcessRunner('git', any())).thenAnswer((_) async {
        pack.createSync(recursive: true);
        return ProcessResult(0, 128, '', 'repository not found');
      });

      // Act
      await expectLater(
        GitHandler(processRunner: mockProcessRunner.call)
            .cloneRepo(repoUrl, targetDirectory),
        throwsA(isA<Exception>()),
      );

      // Assert: the empty folders of the other clone survive
      expect(pack.existsSync(), isTrue);
      expect(Directory(targetDirectory).existsSync(), isFalse);
    });

    test('removes the empty folders git left in the target', () async {
      const repoUrl = 'https://github.com/org/failing.git';
      final targetDirectory = path.join(tempDir.path, 'org', 'failing');
      when(() => mockProcessRunner('git', any())).thenAnswer((_) async {
        Directory(path.join(targetDirectory, '.git', 'objects', 'pack'))
            .createSync(recursive: true);
        return ProcessResult(0, 128, '', 'repository not found');
      });

      await expectLater(
        GitHandler(processRunner: mockProcessRunner.call)
            .cloneRepo(repoUrl, targetDirectory),
        throwsA(isA<Exception>()),
      );

      expect(Directory(path.join(tempDir.path, 'org')).existsSync(), isFalse);
    });

    for (final vanishing in ['target', 'org folder']) {
      test(
        'reports the clone error when the $vanishing cannot be listed',
        () async {
          // Arrange: git left a folder behind that vanishes while it is
          // listed, as it happens on Windows right after git deleted it.
          const repoUrl = 'https://github.com/org/failing.git';
          final orgDirectory = path.join(tempDir.path, 'org');
          final targetDirectory = path.join(orgDirectory, 'failing');
          final vanishingPath = vanishing == 'target'
              ? targetDirectory
              : orgDirectory;
          when(() => mockProcessRunner('git', any())).thenAnswer((_) async {
            Directory(path.join(targetDirectory, '.git', 'objects', 'pack'))
                .createSync(recursive: true);
            return ProcessResult(0, 128, '', 'repository not found');
          });

          Directory real(String p) => Zone.root.run(() => Directory(p));

          // Act
          final error = await IOOverrides.runZoned(
            () async {
              try {
                await GitHandler(processRunner: mockProcessRunner.call)
                    .cloneRepo(repoUrl, targetDirectory);
                return null;
              } catch (e) {
                return e;
              }
            },
            createDirectory: (p) =>
                p == vanishingPath ? _VanishingDirectory(real(p)) : real(p),
          );

          // Assert
          expect(
            rmControls(error.toString()),
            'Exception: Failed to clone repo from $repoUrl: '
            'repository not found',
          );
        },
      );
    }
  });

  group('GitHandler with an unknown ssh host', () {
    const repoUrl = 'git@github.com:ggsuite/gg.git';
    const unknownHost =
        'No ED25519 host key is known for github.com and you have '
        'requested strict checking.\r\nHost key verification failed.\r\n'
        'fatal: Could not read from remote repository.';

    late Directory tempDir;
    late String targetDirectory;
    late MockProcessRunner mockProcessRunner;
    late MockSshHostKeys sshHostKeys;
    late _Prompts prompts;
    late List<String> messages;
    late List<int> exitCodes;

    String log() => rmControls(messages.join('\n'));

    GitHandler handler({bool hasTerminal = true}) => GitHandler(
      processRunner: mockProcessRunner.call,
      ggLog: messages.add,
      sshHostKeys: sshHostKeys,
      prompts: prompts,
      hasTerminal: () => hasTerminal,
    );

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('git_handler_ssh');
      targetDirectory = path.join(tempDir.path, 'ggsuite', 'gg');
      mockProcessRunner = MockProcessRunner();
      sshHostKeys = MockSshHostKeys();
      prompts = _Prompts(yes: true);
      messages = [];
      // The first clone fails for the unknown host, the next one works.
      exitCodes = [128, 0];
      when(() => mockProcessRunner('git', any())).thenAnswer((_) async {
        final exitCode = exitCodes.isEmpty ? 128 : exitCodes.removeAt(0);
        return ProcessResult(0, exitCode, '', exitCode == 0 ? '' : unknownHost);
      });
      when(() => sshHostKeys.scan(repoUrl))
          .thenAnswer((_) async => [SshHostKey.example]);
      when(() => sshHostKeys.knownHostsPath).thenReturn('known_hosts');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('adds the trusted key and clones again', () async {
      await handler().cloneRepo(repoUrl, targetDirectory);

      verify(() => sshHostKeys.trust([SshHostKey.example])).called(1);
      verify(() => mockProcessRunner('git', any())).called(2);
      expect(prompts.asked, ['Trust github.com and add it to known_hosts?']);
      expect(prompts.defaults, [true]);
      expect(log(), contains('SSH does not know github.com yet.'));
      expect(
        log(),
        contains(
          'ED25519 key fingerprint: '
          'SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU',
        ),
      );
      expect(log(), contains('✓ Matches the fingerprint published for'));
      expect(log(), contains('✓ Added github.com to known_hosts.'));
    });

    test('throws with the next step when the user declines', () async {
      prompts = _Prompts(yes: false);
      final gitHandler = handler();

      await expectLater(
        gitHandler.cloneRepo(repoUrl, targetDirectory),
        throwsA(
          isA<SshSetupException>().having(
            (e) => rmControls(e.toString()),
            'message',
            allOf(
              startsWith('Exception: Failed to clone repo from $repoUrl:'),
              contains('Host key verification failed.'),
              contains('Run "git ls-remote $repoUrl" once'),
            ),
          ),
        ),
      );
      verifyNever(() => sshHostKeys.trust(any()));

      // A declined host is not asked about again.
      exitCodes = [128];
      await expectLater(
        gitHandler.cloneRepo(repoUrl, '${targetDirectory}2'),
        throwsA(isA<SshSetupException>()),
      );
      expect(prompts.asked, hasLength(1));
    });

    test('asks once for clones of the same host running in parallel', () async {
      exitCodes = [128, 128, 0, 0];
      final gitHandler = handler();

      await Future.wait([
        gitHandler.cloneRepo(repoUrl, targetDirectory),
        gitHandler.cloneRepo(repoUrl, '${targetDirectory}2'),
      ]);

      expect(prompts.asked, hasLength(1));
      verify(() => sshHostKeys.trust(any())).called(1);
      verify(() => mockProcessRunner('git', any())).called(4);
    });

    test('refuses a key that differs from the published one', () async {
      when(() => sshHostKeys.scan(repoUrl)).thenAnswer(
        (_) async => [
          SshHostKey.fromLine('github.com ssh-ed25519 ${'A' * 68}'),
        ],
      );

      await expectLater(
        handler().cloneRepo(repoUrl, targetDirectory),
        throwsA(isA<SshSetupException>()),
      );

      expect(prompts.asked, isEmpty);
      verifyNever(() => sshHostKeys.trust(any()));
      expect(
        log(),
        contains('✗ Differs from the fingerprints published for github.com.'),
      );
      expect(log(), contains('✗ The key of github.com is not trusted.'));
    });

    test('says when no fingerprint is published for the host', () async {
      const otherUrl = 'git@example.com:repo.git';
      when(() => sshHostKeys.scan(otherUrl)).thenAnswer(
        (_) async => [SshHostKey.fromLine('example.com ssh-ed25519 AAAA')],
      );

      await handler().cloneRepo(otherUrl, targetDirectory);

      expect(prompts.defaults, [false]);
      expect(
        log(),
        contains('! No published fingerprint is known for example.com.'),
      );
    });

    test('reports a known_hosts file it cannot write and asks again', () async {
      when(() => sshHostKeys.trust(any()))
          .thenThrow(const FileSystemException('Access denied', 'known_hosts'));
      exitCodes = [128, 128];
      final gitHandler = handler();

      await expectLater(
        gitHandler.cloneRepo(repoUrl, targetDirectory),
        throwsA(
          isA<SshSetupException>()
              .having((e) => e.host, 'host', 'github.com')
              .having(
                (e) => e.message,
                'message',
                contains('SSH does not know github.com yet.'),
              ),
        ),
      );
      expect(log(), contains('✗ Could not add the key of github.com:'));
      expect(Directory(targetDirectory).parent.existsSync(), isFalse);

      // The host is offered again by the next clone.
      await expectLater(
        gitHandler.cloneRepo(repoUrl, targetDirectory),
        throwsA(isA<SshSetupException>()),
      );
      expect(prompts.asked, hasLength(2));
    });

    test('says when ssh reads another known_hosts file', () async {
      exitCodes = [128, 128];

      await expectLater(
        handler().cloneRepo(repoUrl, targetDirectory),
        throwsA(
          isA<SshSetupException>().having(
            (e) => rmControls(e.message),
            'message',
            contains(
              'The key of github.com was added to known_hosts, but ssh '
              'still does not know the host',
            ),
          ),
        ),
      );
    });

    test('shows the dialogs of different hosts one after another', () async {
      const otherUrl = 'git@example.com:org/repo.git';
      when(() => sshHostKeys.scan(otherUrl)).thenAnswer(
        (_) async => [SshHostKey.fromLine('example.com ssh-ed25519 AAAA')],
      );
      exitCodes = [128, 128, 0, 0];
      prompts = _Prompts(
        yes: true,
        answerDelay: const Duration(milliseconds: 20),
      );
      final gitHandler = handler();

      await Future.wait([
        gitHandler.cloneRepo(repoUrl, targetDirectory),
        gitHandler.cloneRepo(otherUrl, '${targetDirectory}2'),
      ]);

      expect(prompts.asked, hasLength(2));
      expect(prompts.mostOpenAtOnce, 1);
    });

    test('offers a host again that could not be scanned', () async {
      when(() => sshHostKeys.scan(repoUrl)).thenAnswer((_) async => []);
      exitCodes = [128, 128];
      final gitHandler = handler();

      for (final target in [targetDirectory, '${targetDirectory}2']) {
        await expectLater(
          gitHandler.cloneRepo(repoUrl, target),
          throwsA(isA<SshSetupException>()),
        );
      }

      verify(() => sshHostKeys.scan(repoUrl)).called(2);
      expect(prompts.asked, isEmpty);
    });

    test('does not ask without a terminal', () async {
      await expectLater(
        handler(hasTerminal: false).cloneRepo(repoUrl, targetDirectory),
        throwsA(isA<SshSetupException>()),
      );

      verifyNever(() => sshHostKeys.scan(any()));
      expect(prompts.asked, isEmpty);
    });

    group('remoteExists', () {
      test('asks to trust an unknown host and asks git again', () async {
        // exitCodes: the first ls-remote fails for the host, the next works.
        expect(await handler().remoteExists(repoUrl), isTrue);

        expect(prompts.asked, hasLength(1));
        verify(() => sshHostKeys.trust([SshHostKey.example])).called(1);
        verify(() => mockProcessRunner('git', ['ls-remote', repoUrl]))
            .called(2);
      });

      test('logs the next step once per host when ssh fails', () async {
        exitCodes = [128, 128];
        final gitHandler = handler(hasTerminal: false);

        expect(await gitHandler.remoteExists(repoUrl), isFalse);
        expect(
          await gitHandler.remoteExists('git@github.com:other/repo.git'),
          isFalse,
        );

        final hints = messages
            .map(rmControls)
            .where((m) => m.startsWith('SSH does not know github.com yet.'));
        expect(hints, hasLength(1));
      });

      test('logs nothing for a repository that does not exist', () async {
        when(() => mockProcessRunner('git', ['ls-remote', repoUrl])).thenAnswer(
          (_) async => ProcessResult(0, 128, '', 'Repository not found.'),
        );

        expect(await handler().remoteExists(repoUrl), isFalse);

        expect(messages, isEmpty);
        expect(prompts.asked, isEmpty);
      });
    });

    test('does not ask for a url without ssh', () async {
      const httpsUrl = 'https://github.com/ggsuite/gg.git';

      await expectLater(
        handler().cloneRepo(httpsUrl, targetDirectory),
        throwsA(
          isA<SshSetupException>().having(
            (e) => e.message,
            'message',
            contains('SSH does not know the host yet.'),
          ),
        ),
      );

      expect(prompts.asked, isEmpty);
    });

    test('reads keys and asks with the defaults of gg', () {
      // Constructed without ssh helpers: reads keys with git, asks with
      // GgPrompts.current and checks stdin and stdout for a terminal.
      expect(GitHandler(), isA<GitHandler>());
    });
  });
}

/// Answers every yes/no question with [yes] after [answerDelay] and records
/// it, and how many questions were open at the same time.
class _Prompts extends GgPrompts {
  _Prompts({required this.yes, this.answerDelay = Duration.zero});

  final bool yes;
  final Duration answerDelay;
  final asked = <String>[];
  final defaults = <bool>[];
  var mostOpenAtOnce = 0;
  var _open = 0;

  @override
  Future<bool> confirm({required String prompt, bool defaultValue = true}) {
    defaults.add(defaultValue);
    return super.confirm(prompt: prompt, defaultValue: defaultValue);
  }

  @override
  Future<int> select({
    required String prompt,
    required List<String> options,
    int initialIndex = 0,
  }) async {
    asked.add(prompt);
    _open++;
    if (_open > mostOpenAtOnce) {
      mostOpenAtOnce = _open;
    }
    await Future<void>.delayed(answerDelay);
    _open--;
    return yes ? 0 : 1;
  }

  @override
  Future<String> input({
    required String prompt,
    String? defaultValue,
    String? initialText,
    bool asMessageEditor = false,
  }) async => fail('asks no text');
}

/// A folder that exists but is gone as soon as it is listed.
class _VanishingDirectory implements Directory {
  _VanishingDirectory(this._real);

  final Directory _real;

  @override
  String get path => _real.path;

  @override
  Directory get parent => _real.parent;

  @override
  bool existsSync() => _real.existsSync();

  @override
  void createSync({bool recursive = false}) =>
      _real.createSync(recursive: recursive);

  @override
  void deleteSync({bool recursive = false}) =>
      _real.deleteSync(recursive: recursive);

  @override
  List<FileSystemEntity> listSync({
    bool recursive = false,
    bool followLinks = true,
  }) => throw PathNotFoundException(
    path,
    const OSError('The system cannot find the path specified.', 3),
    'Directory listing failed',
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
