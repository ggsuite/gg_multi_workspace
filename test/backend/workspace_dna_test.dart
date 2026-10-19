// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_multi_workspace/src/backend/workspace_dna.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

const _block =
    '$claudeMdStartMarker\n\n# gg workflow\n\nUse the skills.\n\n'
    '$claudeMdEndMarker';

void main() {
  late Directory tempDir;
  final messages = <String>[];
  final dnaCalls = <List<String>>[];

  void ggLog(String message) => messages.add(rmControls(message));

  File file(String rel) => File(path.join(tempDir.path, rel));

  /// The folders the `gg dna` calls ran in, one per `--target`.
  final targets = <String>{};

  /// Stands in for `gg dna init/add/build`: leaves in the `--target`
  /// folder — always an empty temporary one — what a real run leaves
  /// there: the pub scaffold and the `dna/` folder, the resolved
  /// [version] in the lock, a CLAUDE.md holding the managed block and
  /// one skill.
  RunDna fakeDna({String version = '0.5.1'}) => (args) async {
    dnaCalls.add(args);
    final target = args[args.indexOf('--target') + 1];
    targets.add(target);
    File at(String rel) => File(path.join(target, rel));
    switch (args.first) {
      case 'init':
        at('pubspec.yaml').writeAsStringSync('name: ws\n');
        at(path.join('dna', '_dna.json'))
          ..createSync(recursive: true)
          ..writeAsStringSync('{}\n');
      case 'add':
        at('pubspec.lock').writeAsStringSync(
          'packages:\n'
          '  dna_gg:\n'
          '    dependency: "direct dev"\n'
          '    version: "$version"\n',
        );
        Directory(path.join(target, '.dart_tool')).createSync();
      case 'build':
        expect(at('CLAUDE.md').existsSync(), isFalse);
        at('CLAUDE.md').writeAsStringSync('$_block\n');
        at(path.join('.claude', 'skills', 'gg', 'SKILL.md'))
          ..createSync(recursive: true)
          ..writeAsStringSync('# gg $version\n');
    }
  };

  setUp(() {
    messages.clear();
    dnaCalls.clear();
    targets.clear();
    tempDir = Directory.systemTemp.createTempSync('workspace_dna_test_');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  /// The names [tempDir] holds, sorted.
  List<String> rootEntries() =>
      tempDir.listSync().map((e) => path.basename(e.path)).toList()..sort();

  group('instantiateWorkspaceDna', () {
    test('runs init, add, build in a temporary folder and copies only '
        '.claude and CLAUDE.md into the root', () async {
      await instantiateWorkspaceDna(
        root: tempDir.path,
        runDna: fakeDna(),
        ggLog: ggLog,
      );

      expect(targets, hasLength(1));
      final build = targets.single;
      expect(build, isNot(contains(r'\')));
      expect(
        path.equals(build, tempDir.path),
        isFalse,
        reason: 'helix must never run in the workspace root',
      );
      expect(dnaCalls, [
        ['init', '--target', build, '--language', 'dart', '--quiet'],
        ['add', workspaceDnaLayer, '--target', build, '--workspace', '--quiet'],
        ['build', '--target', build, '--workspace', '--quiet'],
      ]);
      expect(rootEntries(), ['.claude', 'CLAUDE.md']);
      expect(file('CLAUDE.md').readAsStringSync(), '$_block\n');
      expect(
        file(path.join('.claude', 'skills', 'gg', 'SKILL.md')).existsSync(),
        isTrue,
      );
      expect(Directory(build).existsSync(), isFalse);
      expect(messages.last, '✓ dna_gg instantiated in the workspace');
    });

    test(
      'keeps the own text of CLAUDE.md and the own files of .claude',
      () async {
        file('CLAUDE.md').writeAsStringSync(
          '# My notes\n\n$claudeMdStartMarker\nold\n$claudeMdEndMarker\n\n'
          '## More notes\n',
        );
        file(path.join('.claude', 'settings.local.json'))
          ..createSync(recursive: true)
          ..writeAsStringSync('{}\n');
        file(path.join('.claude', 'skills', 'gg', 'SKILL.md'))
          ..createSync(recursive: true)
          ..writeAsStringSync('# gg old\n');

        await instantiateWorkspaceDna(
          root: tempDir.path,
          runDna: fakeDna(version: '0.6.0'),
          ggLog: ggLog,
        );

        expect(
          file('CLAUDE.md').readAsStringSync(),
          '# My notes\n\n$_block\n\n## More notes\n',
        );
        expect(
          file(path.join('.claude', 'settings.local.json')).existsSync(),
          isTrue,
        );
        expect(
          file(path.join('.claude', 'skills', 'gg', 'SKILL.md'))
              .readAsStringSync(),
          '# gg 0.6.0\n',
        );
      },
    );

    test('stamps the version the lock resolved', () async {
      await instantiateWorkspaceDna(
        root: tempDir.path,
        runDna: fakeDna(version: '0.7.0'),
        ggLog: ggLog,
      );
      expect(file(dnaVersionStampPath).readAsStringSync(), '0.7.0');
    });

    test('writes no stamp without a lock or a dna_gg entry in it', () async {
      // No lock at all — and no output either: the root stays empty.
      await instantiateWorkspaceDna(
        root: tempDir.path,
        runDna: (_) async {},
        ggLog: ggLog,
      );
      expect(rootEntries(), isEmpty);

      // A lock that does not name dna_gg.
      await instantiateWorkspaceDna(
        root: tempDir.path,
        runDna: (args) async {
          if (args.first == 'add') {
            final target = args[args.indexOf('--target') + 1];
            File(path.join(target, 'pubspec.lock'))
                .writeAsStringSync('packages:\n  other: {}\n');
          }
        },
        ggLog: ggLog,
      );
      expect(file(dnaVersionStampPath).existsSync(), isFalse);
    });

    test('leaves the root untouched when a step fails', () async {
      file('CLAUDE.md').writeAsStringSync('# My notes\n');
      final fake = fakeDna();
      await instantiateWorkspaceDna(
        root: tempDir.path,
        runDna: (args) async {
          if (args.first == 'build') throw Exception('build failed');
          await fake(args);
        },
        ggLog: ggLog,
      );

      expect(rootEntries(), ['CLAUDE.md']);
      expect(file('CLAUDE.md').readAsStringSync(), '# My notes\n');
      expect(Directory(targets.single).existsSync(), isFalse);
      expect(
        messages,
        contains('Could not instantiate dna_gg: Exception: build failed'),
      );
      expect(
        messages.last,
        'Run gg do init workspace in the workspace root to try again.',
      );
    });

    test('names the gg update when helix cannot read the layer', () async {
      await instantiateWorkspaceDna(
        root: tempDir.path,
        runDna: (args) async {
          targets.add(args[args.indexOf('--target') + 1]);
          if (args.first == 'add') {
            throw Exception(
              'dna_gg/dna/_dna.json: format version 2 is not supported — '
              'this helix reads version 1',
            );
          }
        },
        ggLog: ggLog,
      );

      expect(rootEntries(), isEmpty);
      expect(Directory(targets.single).existsSync(), isFalse);
      expect(
        messages.last,
        'The helix inside gg is too old for the latest dna_gg. '
        'Update gg: dart pub global activate gg',
      );
    });

    test('reports a temporary folder that cannot be created', () async {
      await instantiateWorkspaceDna(
        root: tempDir.path,
        runDna: fakeDna(),
        ggLog: ggLog,
        createTemp: () => throw const FileSystemException('no temp'),
      );

      expect(dnaCalls, isEmpty);
      expect(rootEntries(), isEmpty);
      expect(messages.first, contains('Could not instantiate dna_gg'));
      expect(
        messages.last,
        'Run gg do init workspace in the workspace root to try again.',
      );
    });

    test(
      'leaves the root as it was when its CLAUDE.md block cannot be replaced',
      () async {
        const broken = '# My notes\n\n$claudeMdStartMarker\nold\n';
        file('CLAUDE.md').writeAsStringSync(broken);
        file(path.join('.claude', 'skills', 'gg', 'SKILL.md'))
          ..createSync(recursive: true)
          ..writeAsStringSync('# gg old\n');
        file(dnaVersionStampPath).writeAsStringSync('0.4.0');

        await instantiateWorkspaceDna(
          root: tempDir.path,
          runDna: fakeDna(version: '0.6.0'),
          ggLog: ggLog,
        );

        expect(file('CLAUDE.md').readAsStringSync(), broken);
        expect(
          file(path.join('.claude', 'skills', 'gg', 'SKILL.md'))
              .readAsStringSync(),
          '# gg old\n',
        );
        expect(file(dnaVersionStampPath).readAsStringSync(), '0.4.0');
        expect(Directory(targets.single).existsSync(), isFalse);
        expect(
          messages.last,
          'Add the missing "$claudeMdEndMarker" to CLAUDE.md in the '
          'workspace root, then run gg do init workspace there.',
        );
      },
    );

    test('finds its block again behind a lone end marker', () async {
      file('CLAUDE.md').writeAsStringSync('Mentions $claudeMdEndMarker.\n');

      await instantiateWorkspaceDna(
        root: tempDir.path,
        runDna: fakeDna(),
        ggLog: ggLog,
      );

      expect(
        file('CLAUDE.md').readAsStringSync(),
        'Mentions $claudeMdEndMarker.\n\n$_block\n',
      );
      expect(claudeMdBlockIn(tempDir.path), _block);
    });

    test('gives a temporary folder inside a git work tree its own '
        'repository', () async {
      final enclosing = Directory(path.join(tempDir.path, 'repo'))
        ..createSync();
      Directory(path.join(enclosing.path, '.git')).createSync();
      final fake = fakeDna();
      final ownRepo = <bool>[];

      await instantiateWorkspaceDna(
        root: tempDir.path,
        runDna: (args) async {
          final target = args[args.indexOf('--target') + 1];
          ownRepo.add(Directory(path.join(target, '.git')).existsSync());
          await fake(args);
        },
        ggLog: ggLog,
        createTemp: () =>
            Directory(path.join(enclosing.path, 'build'))..createSync(),
      );

      expect(ownRepo, [true, true, true]);
      expect(messages.last, '✓ dna_gg instantiated in the workspace');
    });

    test('reports a git init that fails', () async {
      // A `.git` file that is no gitfile makes `git init` fail.
      final build = Directory(path.join(tempDir.path, 'build'))..createSync();
      File(path.join(build.path, '.git')).writeAsStringSync('garbage\n');

      await instantiateWorkspaceDna(
        root: tempDir.path,
        runDna: fakeDna(),
        ggLog: ggLog,
        createTemp: () => build,
      );

      expect(dnaCalls, isEmpty);
      expect(build.existsSync(), isFalse);
      expect(
        messages,
        contains(
          startsWith('Could not instantiate dna_gg: Exception: git init'),
        ),
      );
    });

    group('removes the scaffold a failed in-root run left', () {
      void seedScaffold({String description = 'A Dart project.'}) {
        file('pubspec.yaml').writeAsStringSync(
          'name: ws\n'
          'description: $description\n'
          'version: 0.1.0\n'
          'publish_to: none\n'
          '\n'
          'dev_dependencies:\n'
          '  dna_gg: ^0.8.0\n'
          '  helix: ^1.11.0\n',
        );
        file('pubspec.lock').writeAsStringSync('packages: {}\n');
        Directory(path.join(tempDir.path, '.dart_tool')).createSync();
        file(path.join('dna', '_dna.json'))
          ..createSync(recursive: true)
          ..writeAsStringSync('{}\n');
      }

      test('once a run succeeds', () async {
        seedScaffold();

        await instantiateWorkspaceDna(
          root: tempDir.path,
          runDna: fakeDna(),
          ggLog: ggLog,
        );

        expect(rootEntries(), ['.claude', 'CLAUDE.md']);
      });

      test('but not when the run fails', () async {
        seedScaffold();

        await instantiateWorkspaceDna(
          root: tempDir.path,
          runDna: (_) async => throw Exception('offline'),
          ggLog: ggLog,
        );

        expect(rootEntries(), [
          '.dart_tool',
          'dna',
          'pubspec.lock',
          'pubspec.yaml',
        ]);
      });

      test('keeps a dna folder holding more than the configs', () async {
        seedScaffold();
        file(path.join('dna', 'notes.md')).writeAsStringSync('mine\n');

        await instantiateWorkspaceDna(
          root: tempDir.path,
          runDna: fakeDna(),
          ggLog: ggLog,
        );

        expect(rootEntries(), ['.claude', 'CLAUDE.md', 'dna']);
      });

      test('never a pubspec.yaml of the user', () async {
        seedScaffold(description: 'My own package.');
        await instantiateWorkspaceDna(
          root: tempDir.path,
          runDna: fakeDna(),
          ggLog: ggLog,
        );
        expect(file('pubspec.yaml').existsSync(), isTrue);

        file('pubspec.yaml').writeAsStringSync('- not a map\n');
        await instantiateWorkspaceDna(
          root: tempDir.path,
          runDna: fakeDna(),
          ggLog: ggLog,
        );
        expect(file('pubspec.yaml').existsSync(), isTrue);

        file('pubspec.yaml').writeAsStringSync('name: [unclosed\n');
        await instantiateWorkspaceDna(
          root: tempDir.path,
          runDna: fakeDna(),
          ggLog: ggLog,
        );
        expect(file('pubspec.yaml').existsSync(), isTrue);
        expect(file('pubspec.lock').existsSync(), isTrue);
      });
    });
  });

  group('latestWorkspaceDnaVersion', () {
    Future<String?> answer(http.Response response) => latestWorkspaceDnaVersion(
      fetcher: (uri) async {
        expect(uri.toString(), 'https://pub.dev/api/packages/dna_gg');
        return response;
      },
    );

    test('reads latest.version from pub.dev', () async {
      expect(
        await answer(http.Response('{"latest":{"version":"0.5.1"}}', 200)),
        '0.5.1',
      );
    });

    test('is null for anything else pub.dev answers', () async {
      expect(await answer(http.Response('gone', 404)), isNull);
      expect(await answer(http.Response('[]', 200)), isNull);
      expect(await answer(http.Response('{"latest":1}', 200)), isNull);
      expect(await answer(http.Response('{"latest":{}}', 200)), isNull);
      expect(await answer(http.Response('not json', 200)), isNull);
    });

    test('is null when pub.dev cannot be reached', () async {
      final version = await latestWorkspaceDnaVersion(
        fetcher: (_) async => throw const SocketException('offline'),
      );
      expect(version, isNull);
    });
  });

  group('refreshWorkspaceDna', () {
    Future<void> refresh(String? latest, {String version = '0.5.1'}) =>
        refreshWorkspaceDna(
          root: tempDir.path,
          runDna: fakeDna(version: version),
          ggLog: ggLog,
          latestVersion: () async => latest,
        );

    test('instantiates a root without DNA', () async {
      await refresh('0.5.1');
      expect(dnaCalls, hasLength(3));
      expect(file(dnaVersionStampPath).readAsStringSync(), '0.5.1');
      expect(messages.last, '✓ dna_gg instantiated in the workspace');
    });

    test('leaves a root alone that carries the latest version', () async {
      await refresh('0.5.1');
      dnaCalls.clear();

      await refresh('0.5.1');
      expect(dnaCalls, isEmpty);
    });

    test('instantiates again when pub.dev has a newer release', () async {
      await refresh('0.5.1');
      dnaCalls.clear();

      await refresh('0.6.0', version: '0.6.0');
      expect(dnaCalls, hasLength(3));
      expect(file(dnaVersionStampPath).readAsStringSync(), '0.6.0');
    });

    test('instantiates again when CLAUDE.md was lost', () async {
      await refresh('0.5.1');
      file('CLAUDE.md').deleteSync();
      dnaCalls.clear();

      await refresh('0.5.1');
      expect(dnaCalls, hasLength(3));
    });

    test('keeps what is there when pub.dev cannot be asked', () async {
      await refresh('0.5.1');
      dnaCalls.clear();

      await refresh(null);
      expect(dnaCalls, isEmpty);
    });

    test('instantiates a root without DNA even offline', () async {
      await refresh(null);
      expect(dnaCalls, hasLength(3));
    });

    test('instantiates again when the managed block was lost', () async {
      await refresh('0.5.1');
      file('CLAUDE.md').writeAsStringSync('# Only my own notes\n');
      dnaCalls.clear();

      await refresh('0.5.1');
      expect(dnaCalls, hasLength(3));
    });
  });

  group('copyWorkspaceDna', () {
    late Directory ticket;

    setUp(() {
      ticket = Directory(path.join(tempDir.path, 'T-1'))..createSync();
    });

    File inTicket(String rel) => File(path.join(ticket.path, rel));

    test('copies only the managed block and all skills', () async {
      file('CLAUDE.md').writeAsStringSync('# My notes\n\n$_block\n\nMore.\n');
      file('.claude/skills/gg/SKILL.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('gg');
      file('.claude/skills/gg-push/SKILL.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('push');
      file(dnaVersionStampPath).writeAsStringSync('0.5.1');

      await copyWorkspaceDna(root: tempDir.path, ticketDir: ticket.path);

      expect(inTicket('CLAUDE.md').readAsStringSync(), '$_block\n');
      expect(inTicket('.claude/skills/gg/SKILL.md').readAsStringSync(), 'gg');
      expect(
        inTicket('.claude/skills/gg-push/SKILL.md').readAsStringSync(),
        'push',
      );
      // The stamp belongs to the root only.
      expect(inTicket(dnaVersionStampPath).existsSync(), isFalse);
    });

    test('leaves the ticket alone when the root has no DNA', () async {
      await copyWorkspaceDna(root: tempDir.path, ticketDir: ticket.path);
      expect(inTicket('CLAUDE.md').existsSync(), isFalse);
      expect(Directory(inTicket('.claude').path).existsSync(), isFalse);
    });

    test('copies no CLAUDE.md without a complete managed block', () async {
      file('CLAUDE.md').writeAsStringSync('# Only my own notes\n');
      await copyWorkspaceDna(root: tempDir.path, ticketDir: ticket.path);
      expect(inTicket('CLAUDE.md').existsSync(), isFalse);

      file('CLAUDE.md')
          .writeAsStringSync('$claudeMdEndMarker\n$claudeMdStartMarker');
      await copyWorkspaceDna(root: tempDir.path, ticketDir: ticket.path);
      expect(inTicket('CLAUDE.md').existsSync(), isFalse);
    });

    test('copies a link as a link', () async {
      final skills = Directory(path.join(tempDir.path, '.claude', 'skills'))
        ..createSync(recursive: true);
      Link(path.join(skills.path, 'shared')).createSync('../shared');

      await copyWorkspaceDna(root: tempDir.path, ticketDir: ticket.path);
      expect(
        Link(inTicket('.claude/skills/shared').path).targetSync(),
        '../shared',
      );
    });
  });

  group('upsertClaudeMdBlock', () {
    test('replaces the block and keeps the text around it', () {
      expect(
        upsertClaudeMdBlock(
          'A\n$claudeMdStartMarker\nold\n$claudeMdEndMarker\nB\n',
          _block,
        ),
        'A\n$_block\nB\n',
      );
    });

    test('appends the block after a blank line when there is none', () {
      expect(
        upsertClaudeMdBlock('# Notes\n\n', _block),
        '# Notes\n\n$_block\n',
      );
      expect(upsertClaudeMdBlock('', _block), '$_block\n');
    });

    test('throws on a start marker without an end marker', () {
      expect(
        () => upsertClaudeMdBlock('$claudeMdStartMarker\nold\n', _block),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('without a matching'),
          ),
        ),
      );
    });
  });

  group('claudeMdBlock', () {
    test('returns the block with its markers, null without one', () {
      expect(claudeMdBlock('before\n$_block\nafter'), _block);
      expect(claudeMdBlock('no block'), isNull);
      expect(claudeMdBlock(claudeMdStartMarker), isNull);
    });
  });

  group('helix runner', () {
    test('helixDnaRunner runs the helix commands under gg dna', () async {
      // `--help` is the one call that touches neither the package managers
      // nor the file system.
      await expectLater(helixDnaRunner(ggLog)(['--help']), completes);
    });
  });
}
