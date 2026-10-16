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

  /// Writes [content] to [relativePath] below the workspace root.
  void write(String relativePath, String content) {
    File(p.join(root.path, relativePath))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('workspace_repo_host_');
    ocean = p.join(root.path, ggMultiOceanFolder);
    write(
      '.ocean/.organizations',
      jsonEncode([
        {'id': '1', 'name': 'ggsuite', 'url': 'https://github.com/ggsuite/'},
      ]),
    );
    write('.ocean/ggsuite/dna_ggsuite/pubspec.yaml', 'name: dna_ggsuite\n');
    write('.ocean/ggsuite/dna_ggsuite/dna/_dna.json', '{}');
    write('.ocean/tssuite/dna_tssuite/pubspec.yaml', 'name: dna_tssuite\n');
    write(
      '.ocean/tssuite/dna_tssuite/package.json',
      '{"name": "@tssuite/dna-tssuite"}',
    );
    write('.ocean/tssuite/dna_tssuite/dna/_dna.json', '{}');
    write('.ocean/tssuite/dna_plain/package.json', '{"name": "dna-plain"}');
    write('.ocean/ggsuite/gg_existing/pubspec.yaml', 'name: gg_existing\n');
    write('.ocean/ggsuite/broken/pubspec.yaml', 'name: [unclosed');
    write('.ocean/ggsuite/list/package.json', '[]');
    write('.ocean/ggsuite/dna_broken/pubspec.yaml', '- a list');
    write('.ocean/ggsuite/dna_broken/dna/_dna.json', '{}');
    write('.ocean/ggsuite/.hidden/pubspec.yaml', 'name: hidden\n');
    write('.ocean/.git/config', '');
    write('ticket/ticket.json', '{}');
    write('ticket/taken/README.md', '');
  });

  tearDown(() => root.deleteSync(recursive: true));

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
    group('knownOrgs()', () {
      test('lists the registered orgs and the org folders once', () async {
        expect(await host().knownOrgs(), ['ggsuite', 'tssuite']);
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
        expect(candidates.map((c) => c.ref), ['dna_ggsuite', 'dna_tssuite']);
        expect(candidates.map((c) => c.label), ['dna_ggsuite', 'dna_tssuite']);
      });

      test('offers the npm names of the DNA repos for TypeScript', () {
        final spec = RepoSpec.example(language: RepoLanguage.typescript);
        final candidates = host().dnaCandidates(spec);
        expect(candidates.map((c) => c.ref), ['@tssuite/dna-tssuite']);
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
    });

    // #########################################################################
    test('targetDir() is the org folder in the ocean', () {
      expect(
        host().targetDir(RepoSpec.example(org: 'ggsuite', name: 'gg_new')).path,
        p.join(ocean, 'ggsuite', 'gg_new'),
      );
    });

    // #########################################################################
    group('check()', () {
      test('has nothing against a new name', () async {
        expect(await host().check(RepoSpec.example(name: 'gg_new')), isEmpty);
      });

      test('rejects the name of a gg command', () async {
        final problems = await host().check(RepoSpec.example(name: 'can'));
        expect(problems.single, contains('is a gg command'));
      });

      test('rejects a package name the ocean already has', () async {
        final spec = RepoSpec.example(org: 'tssuite', name: 'gg_existing');
        final problems = await host().check(spec);
        expect(problems.single, contains('already has a package'));
      });

      test('does not count the target folder itself', () async {
        final spec = RepoSpec.example(org: 'ggsuite', name: 'gg_existing');
        expect(await host().check(spec), isEmpty);
      });

      test('rejects a folder the ticket already has', () async {
        final inTicket = p.join(root.path, 'ticket');
        final problems = await host(executionPath: inTicket)
            .check(RepoSpec.example(name: 'taken'));
        expect(problems.single, contains('ticket already has a folder'));
      });
    });

    // #########################################################################
    group('afterCreateDescription()', () {
      final spec = RepoSpec.example();

      test('names the ticket inside a ticket', () {
        final inTicket = p.join(root.path, 'ticket');
        expect(
          host(executionPath: inTicket).afterCreateDescription(spec),
          'add it to the ticket ticket',
        );
      });

      test('keeps the repository in the ocean otherwise', () {
        final inTicket = p.join(root.path, 'ticket');
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
      test('registers the org and adds the repo to the ticket', () async {
        final added = <String>[];
        final inTicket = p.join(root.path, 'ticket');
        final spec = RepoSpec.example(org: 'neworg', name: 'gg_new');

        await host(
          executionPath: inTicket,
          add:
              ({
                required name,
                required ticketPath,
                required oceanPath,
                required ggLog,
              }) async {
                added.add('$name $ticketPath $oceanPath');
              },
        ).afterCreate(spec: spec, directory: root, ggLog: (_) {});

        expect(added, ['gg_new $inTicket $ocean']);
        final orgs = File(p.join(ocean, '.organizations')).readAsStringSync();
        expect(orgs, contains('neworg'));
      });

      test('adds nothing outside of a ticket', () async {
        await host(
          add: ({
            required name,
            required ticketPath,
            required oceanPath,
            required ggLog,
          }) async => fail('must not add'),
        ).afterCreate(spec: RepoSpec.example(), directory: root, ggLog: (_) {});
      });
    });
  });
}
