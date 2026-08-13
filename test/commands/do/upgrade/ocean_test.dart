@Timeout(Duration(minutes: 2))
library;

// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_multi_core/gg_multi_core.dart';
import 'package:gg_multi_workspace/src/backend/git_handler.dart';
import 'package:gg_multi_workspace/src/commands/do/upgrade/ocean.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

class MockGitCloner extends Mock implements GitHandler {}

class MockGitHubPlatform extends Mock implements GitHubPlatform {}

class MockAzureDevOpsPlatform extends Mock implements AzureDevOpsPlatform {}

void main() {
  group('UpdateOceanCommand', () {
    late Directory tempDir;
    late String oceanPath;
    late MockGitCloner gitCloner;
    late MockGitHubPlatform gitHub;
    late MockAzureDevOpsPlatform azure;
    final messages = <String>[];

    void ggLog(String message) => messages.add(rmControls(message));

    // .........................................................................
    /// Creates `<ocean>/<org>/<repo>` with a git remote pointing at [url].
    Directory createRepo(String org, String repo, String url) {
      final dir = Directory(path.join(oceanPath, org, repo))
        ..createSync(recursive: true);
      Directory(path.join(dir.path, '.git')).createSync();
      File(path.join(dir.path, '.git', 'config')).writeAsStringSync(
        '[remote "origin"]\n\turl = $url\n\tfetch = +refs/heads/*\n',
      );
      return dir;
    }

    // .........................................................................
    void writeOrganizations(String json) {
      File(path.join(oceanPath, '.organizations')).writeAsStringSync(json);
      OrganizationUtils.clearCache();
    }

    // .........................................................................
    Future<void> run(List<String> args, {String command = 'ocean'}) async {
      final runner = CommandRunner<void>('test', 'UpdateOceanCommand Test')
        ..addCommand(
          UpdateOceanCommand(
            ggLog: ggLog,
            rootPath: tempDir.path,
            gitCloner: gitCloner,
            gitHubPlatform: gitHub,
            azureDevOpsPlatform: azure,
          ),
        );
      await runner.run([command, ...args]);
    }

    // .........................................................................
    Repository ghRepo(String org, String name) => Repository(
      name: name,
      httpsUrl: 'https://github.com/$org/$name',
      sshUrl: 'git@github.com:$org/$name.git',
    );

    setUp(() {
      messages.clear();
      OrganizationUtils.clearCache();
      gitCloner = MockGitCloner();
      gitHub = MockGitHubPlatform();
      azure = MockAzureDevOpsPlatform();
      when(() => gitCloner.cloneRepo(any(), any())).thenAnswer((_) async {});

      tempDir = Directory.systemTemp.createTempSync('update_ocean_test');
      oceanPath = path.join(tempDir.path, ggMultiOceanFolder);
      Directory(oceanPath).createSync(recursive: true);
      writeOrganizations(
        '[{"id":"1","name":"ggsuite","url":"https://github.com/ggsuite/"}]',
      );
    });

    tearDown(() {
      OrganizationUtils.clearCache();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    // .........................................................................
    test('describes itself', () {
      final command = UpdateOceanCommand(ggLog: ggLog, rootPath: tempDir.path);
      expect(command.name, 'ocean');
      expect(command.aliases, [
        'master',
      ], reason: 'The former command name must keep working as an alias.');
      expect(
        command.description,
        'Sync the ocean with the registered organizations',
      );
    });

    // .........................................................................
    test('still answers to the legacy alias »master«', () async {
      createRepo('ggsuite', 'gg_one', 'git@github.com:ggsuite/gg_one.git');
      when(() => gitHub.fetchOrgRepos('ggsuite'))
          .thenAnswer((_) async => [ghRepo('ggsuite', 'gg_one')]);

      await run([], command: 'master');

      expect(messages.join('\n'), contains('The ocean is up to date'));
    });

    // .........................................................................
    group('adds repositories', () {
      test('that the organization has and ocean lacks', () async {
        createRepo('ggsuite', 'gg_one', 'git@github.com:ggsuite/gg_one.git');
        when(() => gitHub.fetchOrgRepos('ggsuite')).thenAnswer(
          (_) async => [ghRepo('ggsuite', 'gg_one'), ghRepo('ggsuite', 'gg')],
        );

        await run([]);

        verify(
          () => gitCloner.cloneRepo(
            'git@github.com:ggsuite/gg.git',
            path.join(oceanPath, 'ggsuite', 'gg'),
          ),
        ).called(1);
        expect(messages, contains('✓ Adding ggsuite/gg'));
        expect(
          messages.last,
          contains('1 added, 0 moved to the trash, 1 organization(s)'),
        );
      });

      test('but leaves the ones already present alone', () async {
        createRepo('ggsuite', 'gg_one', 'git@github.com:ggsuite/gg_one.git');
        when(() => gitHub.fetchOrgRepos('ggsuite'))
            .thenAnswer((_) async => [ghRepo('ggsuite', 'gg_one')]);

        await run([]);

        verifyNever(() => gitCloner.cloneRepo(any(), any()));
        expect(messages.last, contains('ocean is up to date'));
      });

      test('matching by remote url, not by folder name', () async {
        // The folder carries the package name, the remote the repo name.
        createRepo(
          'ggsuite',
          'gg_one_pkg',
          'git@github.com:ggsuite/gg_one.git',
        );
        when(() => gitHub.fetchOrgRepos('ggsuite'))
            .thenAnswer((_) async => [ghRepo('ggsuite', 'gg_one')]);

        await run([]);

        verifyNever(() => gitCloner.cloneRepo(any(), any()));
      });
    });

    // .........................................................................
    group('removes repositories', () {
      test('that the organization does not offer anymore', () async {
        final gone = createRepo(
          'ggsuite',
          'gg_gone',
          'git@github.com:ggsuite/gg_gone.git',
        );
        createRepo('ggsuite', 'gg_one', 'git@github.com:ggsuite/gg_one.git');
        when(() => gitHub.fetchOrgRepos('ggsuite'))
            .thenAnswer((_) async => [ghRepo('ggsuite', 'gg_one')]);

        await run([]);

        expect(gone.existsSync(), isFalse);
        expect(
          Directory(
            path.join(
              tempDir.path,
              ggMultiTrashFolder,
              ggMultiOceanFolder,
              'ggsuite',
              'gg_gone',
            ),
          ).existsSync(),
          isTrue,
        );
        expect(messages, contains('🗑️ Moving ggsuite/gg_gone to the trash'));
        expect(messages.last, contains('0 added, 1 moved to the trash'));
      });

      test(
        'and drops the organization folder that lost its last repo',
        () async {
          createRepo('other', 'lonely', 'git@github.com:other/lonely.git');
          writeOrganizations(
            '[{"id":"1","name":"other","url":"https://github.com/other/"}]',
          );
          when(() => gitHub.fetchOrgRepos('other')).thenAnswer((_) async => []);

          await run([]);

          expect(
            Directory(path.join(oceanPath, 'other')).existsSync(),
            isFalse,
          );
        },
      );

      test('but never one whose remote url is missing', () async {
        final noGit = Directory(path.join(oceanPath, 'ggsuite', 'no_remote'))
          ..createSync(recursive: true);
        File(path.join(noGit.path, 'pubspec.yaml'))
            .writeAsStringSync('name: no_remote\n');
        when(() => gitHub.fetchOrgRepos('ggsuite')).thenAnswer((_) async => []);

        await run([]);

        expect(noGit.existsSync(), isTrue);
      });

      test('but never one whose remote url cannot be parsed', () async {
        final weird = createRepo('ggsuite', 'weird', 'not-a-url');

        when(() => gitHub.fetchOrgRepos('ggsuite')).thenAnswer((_) async => []);

        await run([]);

        expect(weird.existsSync(), isTrue);
      });

      test('but never one of an unregistered organization', () async {
        final foreign = createRepo(
          'foreign',
          'repo',
          'git@github.com:foreign/repo.git',
        );
        when(() => gitHub.fetchOrgRepos('ggsuite')).thenAnswer((_) async => []);

        await run([]);

        expect(foreign.existsSync(), isTrue);
      });
    });

    // .........................................................................
    group('azure organizations', () {
      test('are fetched with their project', () async {
        writeOrganizations(
          '[{"id":"1","name":"acme","project_name":"proj",'
          '"url":"https://ssh.dev.azure.com:v3/acme/proj/"}]',
        );
        when(() => azure.fetchOrgRepos('acme', project: 'proj'))
            .thenAnswer((_) async => []);

        await run([]);

        verify(() => azure.fetchOrgRepos('acme', project: 'proj')).called(1);
      });

      test(
        'never touch the repos of another project of the same account',
        () async {
          writeOrganizations(
            '[{"id":"1","name":"acme","project_name":"proj",'
            '"url":"https://ssh.dev.azure.com:v3/acme/proj/"}]',
          );
          final other = createRepo(
            'other_project',
            'repo',
            'https://dev.azure.com/acme/other_project/_git/repo',
          );
          when(() => azure.fetchOrgRepos('acme', project: 'proj'))
              .thenAnswer((_) async => []);

          await run([]);

          expect(other.existsSync(), isTrue);
        },
      );
    });

    // .........................................................................
    group('--dry-run', () {
      test('reports without changing anything', () async {
        final gone = createRepo(
          'ggsuite',
          'gg_gone',
          'git@github.com:ggsuite/gg_gone.git',
        );
        when(() => gitHub.fetchOrgRepos('ggsuite'))
            .thenAnswer((_) async => [ghRepo('ggsuite', 'gg_new')]);

        await run(['--dry-run']);

        expect(gone.existsSync(), isTrue);
        verifyNever(() => gitCloner.cloneRepo(any(), any()));
        expect(messages, contains('✓ Would add ggsuite/gg_new'));
        expect(messages, contains('✓ Would move ggsuite/gg_gone to the trash'));
        expect(
          messages.last,
          contains(
            'Would update the ocean: 1 added, '
            '1 moved to the trash',
          ),
        );
      });
    });

    // .........................................................................
    group('failing organizations', () {
      test('are reported and their repos are kept', () async {
        final kept = createRepo(
          'ggsuite',
          'gg_one',
          'git@github.com:ggsuite/gg_one.git',
        );
        when(() => gitHub.fetchOrgRepos('ggsuite'))
            .thenThrow(Exception('gh not authenticated'));

        await run([]);

        expect(kept.existsSync(), isTrue);
        expect(messages, contains('Skipped ggsuite: gh not authenticated'));
      });

      test('with an unsupported platform are skipped', () async {
        writeOrganizations(
          '[{"id":"1","name":"gl","url":"https://gitlab.com/gl/"}]',
        );

        await run([]);

        expect(messages.first, contains('Skipped gl: unsupported platform'));
        verifyNever(() => gitHub.fetchOrgRepos(any()));
      });

      test('do not produce a summary when none answered', () async {
        when(() => gitHub.fetchOrgRepos('ggsuite'))
            .thenThrow(Exception('boom'));

        await run([]);

        expect(messages, hasLength(1));
      });
    });

    // .........................................................................
    test('without registered organizations it prints a hint', () async {
      writeOrganizations('[]');

      await run([]);

      expect(
        messages.single,
        contains('No organizations registered. Run gg do add <org-url> first.'),
      );
    });

    // .........................................................................
    test('migrates a flat workspace before comparing', () async {
      // A repo lying flat in the ocean, as gg created it before
      // the organization folders existed.
      final flat = Directory(path.join(oceanPath, 'gg_one'))
        ..createSync(recursive: true);
      Directory(path.join(flat.path, '.git')).createSync();
      File(path.join(flat.path, '.git', 'config')).writeAsStringSync(
        '[remote "origin"]\n\turl = git@github.com:ggsuite/gg_one.git\n',
      );
      when(() => gitHub.fetchOrgRepos('ggsuite'))
          .thenAnswer((_) async => [ghRepo('ggsuite', 'gg_one')]);

      await run([]);

      expect(
        Directory(path.join(oceanPath, 'ggsuite', 'gg_one')).existsSync(),
        isTrue,
      );
      verifyNever(() => gitCloner.cloneRepo(any(), any()));
    });
  });
}
