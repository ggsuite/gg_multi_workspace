// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_create_repo/gg_create_repo.dart';
import 'package:gg_multi_core/gg_multi_core.dart';
import 'package:gg_multi_workspace/src/backend/workspace_repo_host.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late String ocean;
  late String inTicket;

  /// Makes [relativePath] a git checkout whose origin is [url].
  void gitRemote(String relativePath, String url) {
    final dir = p.join(root.path, relativePath);
    Directory(dir).createSync(recursive: true);
    for (final args in [
      ['init', '-q'],
      ['remote', 'add', 'origin', url],
    ]) {
      final result = Process.runSync('git', args, workingDirectory: dir);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }
  }

  /// The orgs `.organizations` lists.
  List<String> registeredOrgs() {
    final file = File(p.join(ocean, '.organizations'));
    final list = jsonDecode(file.readAsStringSync()) as List<dynamic>;
    return [
      for (final org in list) (org as Map<String, dynamic>)['name'] as String,
    ];
  }

  setUp(() async {
    root = Directory.systemTemp.createTempSync('workspace_repo_host_');
    ocean = p.join(root.path, ggMultiOceanFolder);
    inTicket = p.join(root.path, 'ticket');
    await copyDirectory(
      Directory(p.join('test', 'sample_folder', 'workspace_repo_host')),
      root,
    );
    // copyDirectory skips ticket.json, the file that makes a ticket.
    File(p.join(inTicket, 'ticket.json')).writeAsStringSync('{}');
    OrganizationUtils.clearCache();
  });

  tearDown(() {
    OrganizationUtils.clearCache();
    root.deleteSync(recursive: true);
  });

  WorkspaceRepoHost host({
    String? executionPath,
    bool? addToTicket,
    AddToTicket? add,
  }) => WorkspaceRepoHost.example(
    root: root,
    executionPath: executionPath,
    addToTicket: addToTicket,
    add: add,
  );

  group('WorkspaceRepoHost', () {
    // #########################################################################
    group('example()', () {
      test('works without arguments, outside of any workspace', () {
        final example = WorkspaceRepoHost.example();
        expect(example.executionPath, Directory.systemTemp.path);
        expect(
          example.oceanPath,
          p.join(Directory.systemTemp.path, ggMultiOceanFolder),
        );
        expect(example.addToTicket, true);
      });
    });

    // #########################################################################
    group('knownOrgs()', () {
      test('lists the registered orgs and the org folders once', () async {
        expect(await host().knownOrgs(), [
          'ggsuite',
          'audanika-private',
          'othersuite',
          'tssuite',
        ]);
      });

      test('prefers the spelling of an org folder', () async {
        File(p.join(ocean, '.organizations')).writeAsStringSync(
          jsonEncode([
            {'id': '1', 'name': 'mixedorg', 'url': 'https://github.com/x/'},
          ]),
        );
        File(p.join(ocean, 'MixedOrg', 'gg_mixed', 'pubspec.yaml'))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('name: gg_mixed\n');

        final orgs = await host().knownOrgs();

        expect(orgs, contains('MixedOrg'));
        expect(orgs, isNot(contains('mixedorg')));
      });

      test('is empty without an ocean', () async {
        Directory(ocean).deleteSync(recursive: true);
        expect(await host().knownOrgs(), isEmpty);
      });
    });

    // #########################################################################
    group('dnaCandidates()', () {
      test('offers the Dart names of the DNA repos for Dart', () {
        final candidates = host().dnaCandidates(RepoSpec.example());
        expect(candidates.map((c) => c.label), [
          'dna_audanika_private',
          'dna_ggsuite',
          'dna_tssuite',
        ]);
        expect(candidates.map((c) => c.ref), [
          'dna_audanika_private',
          'dna_ggsuite',
          'dna_tssuite',
        ]);
      });

      test('offers the npm names of the DNA repos for TypeScript', () {
        final spec = RepoSpec.example(language: RepoLanguage.typescript);
        final candidates = host().dnaCandidates(spec);
        expect(candidates.map((c) => c.label), [
          '@tssuite/dna-ts-private',
          '@tssuite/dna-tssuite',
        ]);
        expect(candidates.last.ref, '@tssuite/dna-tssuite');
      });

      test('refers to unpublished layers by their git remote', () {
        const dartUrl = 'git@github.com:audanika-private/dna_audanika.git';
        const tsUrl = 'https://github.com/tssuite/dna_ts_private.git';
        gitRemote('.ocean/audanika-private/dna_audanika', dartUrl);
        gitRemote('.ocean/tssuite/dna_ts_private', tsUrl);

        final dart = host().dnaCandidates(RepoSpec.example()).first;
        expect(dart.label, 'dna_audanika_private');
        expect(dart.ref, dartUrl);

        final ts = host()
            .dnaCandidates(RepoSpec.example(language: RepoLanguage.typescript))
            .first;
        expect(ts.label, '@tssuite/dna-ts-private');
        expect(ts.ref, tsUrl);
      });
    });

    // #########################################################################
    group('layerDir()', () {
      String? dirOf(String layer) => host().layerDir(layer)?.path;

      test('finds a layer by its package name', () {
        expect(dirOf('dna_ggsuite'), p.join(ocean, 'ggsuite', 'dna_ggsuite'));
      });

      test('finds a repo with two manifests by either name', () {
        final dir = p.join(ocean, 'tssuite', 'dna_tssuite');
        expect(dirOf('dna_tssuite'), dir);
        expect(dirOf('@tssuite/dna-tssuite'), dir);
      });

      test('finds a layer by its git remote, ssh or https', () {
        gitRemote(
          '.ocean/audanika-private/dna_audanika',
          'git@github.com:audanika-private/dna_audanika.git',
        );
        final dir = p.join(ocean, 'audanika-private', 'dna_audanika');
        expect(
          dirOf('https://github.com/Audanika-Private/dna_audanika.git'),
          dir,
        );
        expect(dirOf('git@github.com:audanika-private/dna_audanika'), dir);
      });

      test('finds a layer by an npm git+https url', () {
        gitRemote(
          '.ocean/tssuite/dna_ts_private',
          'https://github.com/tssuite/dna_ts_private.git',
        );
        expect(
          dirOf('git+https://github.com/tssuite/dna_ts_private.git'),
          p.join(ocean, 'tssuite', 'dna_ts_private'),
        );
      });

      test('finds a layer by an ssh://, git:// or #ref url', () {
        gitRemote(
          '.ocean/tssuite/dna_ts_private',
          'git@github.com:tssuite/dna_ts_private.git',
        );
        final dir = p.join(ocean, 'tssuite', 'dna_ts_private');
        for (final url in [
          'ssh://git@github.com/tssuite/dna_ts_private.git',
          'git+ssh://git@github.com/tssuite/dna_ts_private.git',
          'git://github.com/tssuite/dna_ts_private.git',
          'git+https://github.com/tssuite/dna_ts_private.git#main',
        ]) {
          expect(dirOf(url), dir, reason: url);
        }
      });

      test('is null for a layer the ocean does not have', () {
        expect(dirOf('dna_unknown'), isNull);
        expect(dirOf('https://github.com/ggsuite/dna_unknown.git'), isNull);
        expect(dirOf('https://github.com'), isNull);
      });
    });

    // #########################################################################
    group('presetOrg', () {
      test('is the org folder gg runs in', () {
        final inOrg = p.join(ocean, 'ggsuite', 'gg_existing');
        expect(host(executionPath: inOrg).presetOrg, 'ggsuite');
      });

      test('is null in the ocean itself and outside of it', () {
        expect(host(executionPath: ocean).presetOrg, isNull);
        expect(host().presetOrg, isNull);
      });

      test('is null in a flat repo and in a hidden folder', () {
        final flat = p.join(ocean, 'gg_flat');
        final hidden = p.join(ocean, '.hidden_org', 'gg_hidden');
        expect(host(executionPath: flat).presetOrg, isNull);
        expect(host(executionPath: hidden).presetOrg, isNull);
      });
    });

    // #########################################################################
    group('targetDir()', () {
      String target(String org) =>
          host().targetDir(RepoSpec.example(org: org, name: 'gg_new')).path;

      test('is the org folder in the ocean', () {
        expect(target('ggsuite'), p.join(ocean, 'ggsuite', 'gg_new'));
      });

      test('uses the existing org folder in any case', () {
        expect(target('GgSuite'), p.join(ocean, 'ggsuite', 'gg_new'));
      });

      test('keeps the spelling of a new org, as gg do add does', () {
        final spec = RepoSpec.example(org: 'NewOrg', name: 'gg_new');
        final byAdd = RepoFolderResolver.destination(
          workspacePath: ocean,
          repoUrl: '${spec.webUrl}.git',
          repoName: spec.name,
        );
        expect(target('NewOrg'), p.join(ocean, 'NewOrg', 'gg_new'));
        expect(target('NewOrg'), byAdd);
      });
    });

    // #########################################################################
    group('check()', () {
      Future<List<String>> check(
        RepoSpec spec, {
        String? executionPath,
        bool? addToTicket,
        bool resumes = false,
      }) => host(
        executionPath: executionPath,
        addToTicket: addToTicket,
      ).check(spec, resumes: resumes);

      test('has nothing against a new name', () async {
        expect(await check(RepoSpec.example(name: 'gg_new')), isEmpty);
      });

      test('rejects the name of a gg command', () async {
        for (final name in WorkspaceRepoHost.ggCommandNames) {
          final problems = await check(RepoSpec.example(name: name));
          expect(problems.first, contains('is a gg command'), reason: name);
        }
      });

      test('rejects a package name the ocean already has', () async {
        final spec = RepoSpec.example(org: 'tssuite', name: 'gg_existing');
        final problems = await check(spec);
        expect(problems.first, contains('already has a package'));
        expect(problems.last, contains('exists in org ggsuite too'));
      });

      test('rejects a name another org has, in any case', () async {
        final spec = RepoSpec.example(org: 'ggsuite', name: 'GG_TWIN');
        final problems = await check(spec);
        expect(
          problems.single,
          '»GG_TWIN« exists in org othersuite too: '
          '»gg do add GG_TWIN« would be ambiguous.',
        );
      });

      test('rejects the name of a flat repo of the ocean', () async {
        final spec = RepoSpec.example(org: 'ggsuite', name: 'gg_flat');
        final problems = await check(spec);
        expect(problems.last, contains('exists in the ocean too'));
      });

      test('does not count the target folder itself', () async {
        final spec = RepoSpec.example(org: 'GgSuite', name: 'gg_existing');
        expect(await check(spec), isEmpty);
      });

      test('rejects a folder the ticket already has', () async {
        final spec = RepoSpec.example(name: 'taken');
        final problems = await check(
          spec,
          executionPath: inTicket,
          resumes: true,
        );
        expect(problems.single, 'The ticket already has a folder »taken«.');
      });

      test('ignores the ticket when it does not add to it', () async {
        final spec = RepoSpec.example(name: 'taken');
        expect(
          await check(spec, executionPath: inTicket, addToTicket: false),
          isEmpty,
        );
      });

      test('accepts the repo of the earlier run in the ticket', () async {
        gitRemote('ticket/gg_new', 'git@github.com:ggsuite/gg_new.git');
        final spec = RepoSpec.example(org: 'GgSuite', name: 'gg_new');

        expect(
          await check(spec, executionPath: inTicket, resumes: true),
          isEmpty,
        );
        expect(await check(spec, executionPath: inTicket), [
          'The ticket already has a folder »gg_new«.',
        ]);
      });

      test('rejects another repo of that name in the ticket', () async {
        gitRemote('ticket/gg_new', 'git@github.com:other/gg_new.git');
        final spec = RepoSpec.example(name: 'gg_new');
        final problems = await check(
          spec,
          executionPath: inTicket,
          resumes: true,
        );
        expect(problems.single, contains('ticket already has a folder'));
      });
    });

    // #########################################################################
    group('afterCreateDescription()', () {
      final spec = RepoSpec.example();

      test('names the ticket inside a ticket', () {
        expect(
          host(executionPath: inTicket).afterCreateDescription(spec),
          'add it to the ticket ticket',
        );
      });

      test('keeps the repository in the ocean otherwise', () {
        expect(
          host(
            executionPath: inTicket,
            addToTicket: false,
          ).afterCreateDescription(spec),
          'keep it in the ocean',
        );
        expect(host().afterCreateDescription(spec), 'keep it in the ocean');
      });
    });

    // #########################################################################
    group('afterCreate()', () {
      test('registers the org and adds the repo by its ssh url', () async {
        final added = <String>[];
        final spec = RepoSpec.example(org: 'NewOrg', name: 'gg_new');
        final ticketHost = host(
          executionPath: inTicket,
          add:
              ({
                required url,
                required ticketPath,
                required oceanPath,
                required ggLog,
              }) async {
                added.add('$url $ticketPath $oceanPath');
              },
        );

        await ticketHost.afterCreate(
          spec: spec,
          directory: root,
          ggLog: (_) {},
        );
        await ticketHost.afterCreate(
          spec: spec,
          directory: root,
          ggLog: (_) {},
        );

        const url = 'git@github.com:NewOrg/gg_new.git';
        expect(added, List.filled(2, '$url $inTicket $ocean'));
        expect(registeredOrgs(), ['ggsuite', 'NewOrg']);
      });

      test('does not register an org twice in another case', () async {
        final spec = RepoSpec.example(org: 'GgSuite');
        await host().afterCreate(spec: spec, directory: root, ggLog: (_) {});
        expect(registeredOrgs(), ['ggsuite']);
      });

      test('adds nothing outside of a ticket', () async {
        await host(
          add: ({
            required url,
            required ticketPath,
            required oceanPath,
            required ggLog,
          }) async => fail('must not add'),
        ).afterCreate(spec: RepoSpec.example(), directory: root, ggLog: (_) {});
      });
    });

    // #########################################################################
    group('addWithAddCommand()', () {
      const url = 'https://github.com/ggsuite/gg_new.git';

      /// A workspace whose ocean has the new repo, as the creator left it.
      ({String ocean, String ticket}) workspace() {
        final ocean = p.join(root.path, 'add', ggMultiOceanFolder);
        final repo = p.join(ocean, 'ggsuite', 'gg_new');
        final ticket = p.join(root.path, 'add', 'ticket');
        File(p.join(repo, 'pubspec.yaml'))
          ..createSync(recursive: true)
          ..writeAsStringSync(
            'name: gg_new\nversion: 0.0.1\n'
            'environment:\n  sdk: ^3.0.0\n',
          );
        File(p.join(ticket, 'ticket.json'))
          ..createSync(recursive: true)
          ..writeAsStringSync('{}');
        for (final args in [
          ['init', '-q', '--initial-branch=main'],
          ['add', '--all'],
          ['commit', '-qm', 'Initial version'],
          ['remote', 'add', 'origin', url],
        ]) {
          final result = Process.runSync(
            'git',
            args,
            workingDirectory: repo,
            environment: _gitIdentity,
          );
          expect(result.exitCode, 0, reason: '${result.stderr}');
        }
        return (ocean: ocean, ticket: ticket);
      }

      test('copies the ocean repo into the ticket, once', () async {
        final w = workspace();
        Future<void> add() => WorkspaceRepoHost.addWithAddCommand(
          url: url,
          ticketPath: w.ticket,
          oceanPath: w.ocean,
          ggLog: (_) {},
        );

        await add();
        await add();

        final copy = p.join(w.ticket, 'gg_new');
        expect(File(p.join(copy, 'pubspec.yaml')).existsSync(), isTrue);
        expect(RepoFolderResolver.remoteUrl(Directory(copy)), url);
        expect(RepoFolderResolver.repoDirs(w.ticket).map((d) => d.path), [
          copy,
        ]);
      }, timeout: const Timeout(Duration(minutes: 3)));
    });
  });
}

/// The identity of the commits the tests make; CI has none of its own.
const _gitIdentity = {
  'GIT_AUTHOR_NAME': 'Test',
  'GIT_AUTHOR_EMAIL': 'test@example.com',
  'GIT_COMMITTER_NAME': 'Test',
  'GIT_COMMITTER_EMAIL': 'test@example.com',
};
