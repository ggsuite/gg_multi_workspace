// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_multi_core/gg_multi_core.dart';
import 'package:gg_multi_workspace/src/commands/do/rm/repo.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('RemoveRepoCommand', () {
    late Directory tempDir; // workspace root
    late Directory oceanWs;
    late Directory ticketsRoot;
    final messages = <String>[];

    void ggLog(String message) {
      messages.add(rmControls(message));
    }

    CommandRunner<void> runnerAt(String rootPath) {
      return CommandRunner<void>('test', 'RemoveRepoCommand Test')
        ..addCommand(RemoveRepoCommand(ggLog: ggLog, rootPath: rootPath));
    }

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync('remove_test_');
      oceanWs = Directory(path.join(tempDir.path, ggMultiOceanFolder))
        ..createSync(recursive: true);
      ticketsRoot = Directory(path.join(tempDir.path, ggMultiTicketFolder))
        ..createSync(recursive: true);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    group('invoked outside a ticket', () {
      test('refuses without --from-master and names the flag', () async {
        Directory(
          path.join(oceanWs.path, 'project'),
        ).createSync(recursive: true);

        await expectLater(
          runnerAt(tempDir.path).run(['repo', 'project']),
          throwsA(
            isA<Exception>().having(
              (e) => rmControls(e.toString()),
              'message',
              allOf(
                contains('must be called inside a ticket folder'),
                contains('--from-master'),
              ),
            ),
          ),
        );
      });
    });

    group('invoked with --from-master', () {
      test('deletes repo when only in master', () async {
        final repoDir = Directory(path.join(oceanWs.path, 'project'))
          ..createSync(recursive: true);

        await runnerAt(tempDir.path).run(['repo', 'project', '--from-master']);

        expect(repoDir.existsSync(), isFalse);
        expect(messages, ['✓ Deleted repository project from ocean.']);
      });

      test('deletes several repos in one call', () async {
        final repo1 = Directory(path.join(oceanWs.path, 'one'))..createSync();
        final repo2 = Directory(path.join(oceanWs.path, 'two'))..createSync();

        await runnerAt(
          tempDir.path,
        ).run(['repo', 'one', 'two', '--from-master']);

        expect(repo1.existsSync(), isFalse);
        expect(repo2.existsSync(), isFalse);
        expect(messages, [
          '✓ Deleted repository one from ocean.',
          '✓ Deleted repository two from ocean.',
        ]);
      });

      test('refuses to delete the master copy when the repo is also in a '
          'ticket — and lists the offending tickets', () async {
        // Repo in ocean + in ticket "alpha".
        final oceanRepo = Directory(path.join(oceanWs.path, 'shared'))
          ..createSync();
        final alphaDir = Directory(path.join(ticketsRoot.path, 'alpha'))
          ..createSync();
        Directory(path.join(alphaDir.path, 'shared')).createSync();

        await runnerAt(tempDir.path).run(['repo', 'shared', '--from-master']);

        expect(oceanRepo.existsSync(), isTrue);
        expect(
          messages,
          contains('Repository shared is used by the following tickets:'),
        );
        expect(messages, contains(' - alpha'));
        expect(
          messages.any((m) => m.contains('Please remove it from those')),
          isTrue,
        );
        expect(messages.any((m) => m.contains('gg do rm repo shared')), isTrue);
      });

      test('lists multiple tickets that reference the repo', () async {
        Directory(path.join(oceanWs.path, 'r1')).createSync();
        final t1 = Directory(path.join(ticketsRoot.path, 't1'))..createSync();
        Directory(path.join(t1.path, 'r1')).createSync();
        final t2 = Directory(path.join(ticketsRoot.path, 't2'))..createSync();
        Directory(path.join(t2.path, 'r1')).createSync();

        await runnerAt(tempDir.path).run(['repo', 'r1', '--from-master']);

        expect(messages, contains(' - t1'));
        expect(messages, contains(' - t2'));
      });

      test('reports not-found when repo lives nowhere', () async {
        await runnerAt(tempDir.path).run(['repo', 'ghost', '--from-master']);

        expect(
          messages,
          contains('Repository ghost not found in any workspace.'),
        );
      });

      test('works from a sub-folder of the workspace root', () async {
        final repoDir = Directory(path.join(oceanWs.path, 'ggsuite', 'project'))
          ..createSync(recursive: true);
        File(
          path.join(repoDir.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: project\nversion: 1.0.0\n');
        final subDir = Directory(path.join(repoDir.path, 'lib'))
          ..createSync(recursive: true);

        await runnerAt(subDir.path).run(['repo', 'project', '--from-master']);

        expect(repoDir.existsSync(), isFalse);
        expect(messages, contains('✓ Deleted repository project from ocean.'));
      });
    });

    group('invoked from inside a ticket', () {
      test('deletes the repo from this ticket only', () async {
        // alpha-scoped rm must not touch ocean or sibling tickets.
        Directory(path.join(oceanWs.path, 'shared')).createSync();
        final alphaDir = Directory(path.join(ticketsRoot.path, 'alpha'))
          ..createSync();
        final betaDir = Directory(path.join(ticketsRoot.path, 'beta'))
          ..createSync();
        final alphaRepo = Directory(path.join(alphaDir.path, 'shared'))
          ..createSync();
        final betaRepo = Directory(path.join(betaDir.path, 'shared'))
          ..createSync();

        await runnerAt(alphaDir.path).run(['repo', 'shared']);

        expect(alphaRepo.existsSync(), isFalse);
        expect(betaRepo.existsSync(), isTrue);
        expect(
          Directory(path.join(oceanWs.path, 'shared')).existsSync(),
          isTrue,
          reason: 'ocean must never be touched from a ticket-scoped rm',
        );
        expect(messages, ['✓ Deleted repository shared from ticket alpha.']);
      });

      test('reports when the repo is not part of this ticket', () async {
        final alphaDir = Directory(path.join(ticketsRoot.path, 'alpha'))
          ..createSync();

        await runnerAt(alphaDir.path).run(['repo', 'unrelated']);

        expect(
          messages,
          contains('Repository unrelated is not part of ticket alpha.'),
        );
      });

      test('works when invoked from a sub-folder of the ticket', () async {
        final alphaDir = Directory(path.join(ticketsRoot.path, 'alpha'))
          ..createSync();
        final repoDir = Directory(path.join(alphaDir.path, 'ggsuite', 'shared'))
          ..createSync(recursive: true);
        File(
          path.join(repoDir.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: shared\nversion: 1.0.0\n');
        final subDir = Directory(path.join(repoDir.path, 'lib', 'src'))
          ..createSync(recursive: true);

        await runnerAt(subDir.path).run(['repo', 'shared']);

        expect(repoDir.existsSync(), isFalse);
        expect(messages, ['✓ Deleted repository shared from ticket alpha.']);
      });
    });

    group('dependency chain inside a ticket', () {
      // Creates a dart package folder depending on [deps].
      Directory makePackage(
        Directory parent,
        String name, {
        List<String> deps = const [],
      }) {
        final dir = Directory(path.join(parent.path, name))
          ..createSync(recursive: true);
        final buffer = StringBuffer('name: $name\nversion: 1.0.0\n');
        if (deps.isNotEmpty) {
          buffer.writeln('dependencies:');
          for (final dep in deps) {
            buffer.writeln('  $dep: ^1.0.0');
          }
        }
        File(
          path.join(dir.path, 'pubspec.yaml'),
        ).writeAsStringSync(buffer.toString());
        return dir;
      }

      // a -> b -> c
      late Directory alphaDir;
      late Directory a;
      late Directory b;
      late Directory c;

      setUp(() {
        alphaDir = Directory(path.join(ticketsRoot.path, 'alpha'))
          ..createSync();
        a = makePackage(alphaDir, 'a', deps: ['b']);
        b = makePackage(alphaDir, 'b', deps: ['c']);
        c = makePackage(alphaDir, 'c');
      });

      test(
        'throws when the repo sits between two other ticket repos',
        () async {
          await expectLater(
            runnerAt(alphaDir.path).run(['repo', 'b']),
            throwsA(
              isA<Exception>().having(
                (e) => rmControls(e.toString()),
                'message',
                allOf(contains('Cannot remove b'), contains('sits between')),
              ),
            ),
          );

          expect(b.existsSync(), isTrue, reason: 'b must not be deleted');
          expect(
            messages,
            contains('Repository b connects other repos of ticket alpha:'),
          );
          expect(messages, contains(' - a depends on b'));
          expect(messages, contains(' - b depends on c'));
          expect(messages, contains('Please remove a first.'));
        },
      );

      test('deletes a repo nothing else depends on', () async {
        await runnerAt(alphaDir.path).run(['repo', 'a']);

        expect(a.existsSync(), isFalse);
        expect(messages, contains('✓ Deleted repository a from ticket alpha.'));
      });

      test('deletes a repo that has no dependencies in the ticket', () async {
        await runnerAt(alphaDir.path).run(['repo', 'c']);

        expect(c.existsSync(), isFalse);
        expect(messages, contains('✓ Deleted repository c from ticket alpha.'));
      });

      test('deletes the linking repo once its dependents are gone', () async {
        await runnerAt(alphaDir.path).run(['repo', 'a']);
        await runnerAt(alphaDir.path).run(['repo', 'b']);

        expect(b.existsSync(), isFalse);
        expect(messages, contains('✓ Deleted repository b from ticket alpha.'));
      });

      test(
        'removes several repos dependents-first, whatever the given order',
        () async {
          // b sits between a and c — naming it before a would fail without
          // the reordering.
          await runnerAt(alphaDir.path).run(['repo', 'b', 'a']);

          expect(a.existsSync(), isFalse);
          expect(b.existsSync(), isFalse);
          expect(c.existsSync(), isTrue);
        },
      );

      test('removes a whole chain in one call', () async {
        await runnerAt(alphaDir.path).run(['repo', 'c', 'b', 'a']);

        expect(a.existsSync(), isFalse);
        expect(b.existsSync(), isFalse);
        expect(c.existsSync(), isFalse);
      });

      test(
        'an unknown name is reported and does not stop the others',
        () async {
          await runnerAt(alphaDir.path).run(['repo', 'ghost', 'a']);

          expect(a.existsSync(), isFalse);
          expect(
            messages,
            contains('Repository ghost is not part of ticket alpha.'),
          );
        },
      );

      test('deletes a folder that is no package at all', () async {
        final plain = Directory(path.join(alphaDir.path, 'plain'))
          ..createSync();

        await runnerAt(alphaDir.path).run(['repo', 'plain']);

        expect(plain.existsSync(), isFalse);
      });
    });

    group('ticket.json', () {
      late Directory alphaDir;
      late Directory a;
      late Directory b;

      Directory makePackage(Directory parent, String name) {
        final dir = Directory(path.join(parent.path, name))
          ..createSync(recursive: true);
        File(
          path.join(dir.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: $name\nversion: 1.0.0\n');
        return dir;
      }

      // Writes the ticket.json of the ticket folder, listing [repos].
      void writeMarker(Directory ticketDir, List<String> repos) {
        writeTicketJson(
          ticketDir,
          TicketJson(
            issueId: 'alpha',
            description: 'Some ticket',
            repositories: [
              for (final repo in repos) TicketRepo(name: repo, url: ''),
            ],
          ),
        );
      }

      TicketJson markerOf(Directory ticketDir) => readTicketJson(ticketDir)!;

      setUp(() {
        alphaDir = Directory(path.join(ticketsRoot.path, 'alpha'))
          ..createSync();
        writeTicketJson(
          alphaDir,
          const TicketJson(
            issueId: 'alpha',
            description: 'Some ticket',
            repositories: <TicketRepo>[],
          ),
        );
        a = makePackage(alphaDir, 'a');
        b = makePackage(alphaDir, 'b');
        writeMarker(alphaDir, ['a', 'b']);
      });

      test('drops the deleted repo from the ticket.json', () async {
        await runnerAt(alphaDir.path).run(['repo', 'a']);

        expect(a.existsSync(), isFalse);
        final marker = markerOf(alphaDir);
        expect(marker.repositories.map((r) => r.name), ['b']);
        expect(marker.issueId, 'alpha');
        expect(marker.description, 'Some ticket');
        expect(messages, contains('✓ Removed a from ticket.json.'));
      });

      test('never writes a ticket.json into a repository', () async {
        await runnerAt(alphaDir.path).run(['repo', 'a']);

        expect(Directory(path.join(b.path, '.gg')).existsSync(), isFalse);
      });

      test('leaves the marker untouched when the removal is refused', () async {
        // b depends on a → removing a is fine, but make a link two repos.
        File(path.join(b.path, 'pubspec.yaml')).writeAsStringSync(
          'name: b\nversion: 1.0.0\n'
          'dependencies:\n  a: ^1.0.0\n',
        );
        makePackage(alphaDir, 'c');
        writeMarker(alphaDir, ['a', 'b', 'c']);
        File(path.join(a.path, 'pubspec.yaml')).writeAsStringSync(
          'name: a\nversion: 1.0.0\n'
          'dependencies:\n  c: ^1.0.0\n',
        );

        await expectLater(
          runnerAt(alphaDir.path).run(['repo', 'a']),
          throwsA(isA<Exception>()),
        );

        expect(markerOf(alphaDir).repositories.map((r) => r.name), [
          'a',
          'b',
          'c',
        ]);
      });

      test('drops the deleted repo from pubspec_overrides.yaml', () async {
        final c = makePackage(alphaDir, 'c');
        writeMarker(alphaDir, ['a', 'b', 'c']);
        File(path.join(b.path, 'pubspec_overrides.yaml')).writeAsStringSync(
          'dependency_overrides:\n'
          '  a:\n    path: ../a\n'
          '  c:\n    path: ../c\n',
        );
        // c only overrides the deleted repo — its file goes away entirely.
        File(
          path.join(c.path, 'pubspec_overrides.yaml'),
        ).writeAsStringSync('dependency_overrides:\n  a:\n    path: ../a\n');

        await runnerAt(alphaDir.path).run(['repo', 'a']);

        final overridesOfB = File(
          path.join(b.path, 'pubspec_overrides.yaml'),
        ).readAsStringSync();
        expect(overridesOfB, isNot(contains('../a')));
        expect(overridesOfB, contains('../c'));
        expect(
          File(path.join(c.path, 'pubspec_overrides.yaml')).existsSync(),
          isFalse,
        );
        expect(
          messages,
          contains('✓ Removed a from the localized overrides of 2 repo(s).'),
        );
      });

      test('says nothing when no repo overrides the deleted one', () async {
        await runnerAt(alphaDir.path).run(['repo', 'a']);

        expect(
          messages.any((m) => m.contains('the localized overrides of')),
          isFalse,
        );
      });

      test('writes no ticket.json into a ticket that has none', () async {
        File(path.join(alphaDir.path, ticketJsonFileName)).deleteSync();

        await runnerAt(alphaDir.path).run(['repo', 'a']);

        expect(
          File(path.join(alphaDir.path, ticketJsonFileName)).existsSync(),
          isFalse,
        );
        expect(messages.any((m) => m.contains('from ticket.json')), isFalse);
      });
    });

    group('org-prefixed folders', () {
      // Creates a repo folder carrying a pubspec name that differs from the
      // (org-prefixed) folder name.
      Directory makePrefixed(Directory parent, String folder, String pkg) {
        final dir = Directory(path.join(parent.path, folder))
          ..createSync(recursive: true);
        File(
          path.join(dir.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: $pkg\nversion: 1.0.0\n');
        return dir;
      }

      test(
        'deletes a prefixed master folder addressed by package name',
        () async {
          final dir = makePrefixed(oceanWs, 'ggsuite_foo', 'foo');

          await runnerAt(tempDir.path).run(['repo', 'foo', '--from-master']);

          expect(dir.existsSync(), isFalse);
          expect(messages, contains('✓ Deleted repository foo from ocean.'));
        },
      );

      test(
        'finds a prefixed ticket copy when refusing master deletion',
        () async {
          makePrefixed(oceanWs, 'ggsuite_foo', 'foo');
          final alphaDir = Directory(path.join(ticketsRoot.path, 'alpha'))
            ..createSync();
          makePrefixed(alphaDir, 'ggsuite_foo', 'foo');

          await runnerAt(tempDir.path).run(['repo', 'foo', '--from-master']);

          expect(
            messages,
            contains('Repository foo is used by the following tickets:'),
          );
          expect(messages, contains(' - alpha'));
        },
      );

      test('deletes a prefixed folder from inside a ticket', () async {
        final alphaDir = Directory(path.join(ticketsRoot.path, 'alpha'))
          ..createSync();
        final repo = makePrefixed(alphaDir, 'ggsuite_foo', 'foo');

        await runnerAt(alphaDir.path).run(['repo', 'foo']);

        expect(repo.existsSync(), isFalse);
        expect(
          messages,
          contains('✓ Deleted repository foo from ticket alpha.'),
        );
      });
    });

    group('organization folders', () {
      // Creates `<workspace>/<org>/<repo>` as a package folder.
      Directory makeOrgRepo(Directory workspace, String org, String repo) {
        final dir = Directory(path.join(workspace.path, org, repo))
          ..createSync(recursive: true);
        File(
          path.join(dir.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: $repo\nversion: 1.0.0\n');
        return dir;
      }

      test('deletes a repo from its org folder in the master', () async {
        final repo = makeOrgRepo(oceanWs, 'ggsuite', 'project');

        await runnerAt(tempDir.path).run(['repo', 'project', '--from-master']);

        expect(repo.existsSync(), isFalse);
        // The organization folder is gone with its last repo.
        expect(
          Directory(path.join(oceanWs.path, 'ggsuite')).existsSync(),
          isFalse,
        );
      });

      test('keeps the org folder while it holds other repos', () async {
        final repo = makeOrgRepo(oceanWs, 'ggsuite', 'project');
        makeOrgRepo(oceanWs, 'ggsuite', 'other');

        await runnerAt(tempDir.path).run(['repo', 'project', '--from-master']);

        expect(repo.existsSync(), isFalse);
        expect(
          Directory(path.join(oceanWs.path, 'ggsuite')).existsSync(),
          isTrue,
        );
      });

      test('finds a ticket that holds the repo in an org folder', () async {
        final oceanRepo = makeOrgRepo(oceanWs, 'ggsuite', 'shared');
        final alphaDir = Directory(path.join(ticketsRoot.path, 'alpha'))
          ..createSync();
        makeOrgRepo(alphaDir, 'ggsuite', 'shared');

        await runnerAt(tempDir.path).run(['repo', 'shared', '--from-master']);

        expect(oceanRepo.existsSync(), isTrue);
        expect(messages, contains(' - alpha'));
      });

      test('deletes a repo from its org folder in a ticket', () async {
        final alphaDir = Directory(path.join(ticketsRoot.path, 'alpha'))
          ..createSync();
        final repo = makeOrgRepo(alphaDir, 'ggsuite', 'foo');

        await runnerAt(alphaDir.path).run(['repo', 'foo']);

        expect(repo.existsSync(), isFalse);
        expect(
          Directory(path.join(alphaDir.path, 'ggsuite')).existsSync(),
          isFalse,
        );
        expect(
          messages,
          contains('✓ Deleted repository foo from ticket alpha.'),
        );
      });
    });

    test('throws UsageException when missing target argument', () async {
      expect(
        () => runnerAt(tempDir.path).run(['repo']),
        throwsA(isA<UsageException>()),
      );
    });
  });
}
