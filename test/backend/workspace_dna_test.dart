// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_multi_workspace/src/backend/workspace_dna.dart';
import 'package:gg_one/gg_one.dart' show GgPrompts;
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

/// Prompts that record the question and always pick the last option.
class _RecordingPrompts extends GgPrompts {
  String? prompt;
  List<String>? options;

  @override
  Future<int> select({
    required String prompt,
    required List<String> options,
    int initialIndex = 0,
  }) async {
    this.prompt = prompt;
    this.options = options;
    return options.length - 1;
  }

  @override
  Future<String> input({
    required String prompt,
    String? defaultValue,
    String? initialText,
    bool asMessageEditor = false,
  }) async => defaultValue ?? '';
}

const _block =
    '$claudeMdStartMarker\n\n# gg workflow\n\nUse the skills.\n\n'
    '$claudeMdEndMarker';

void main() {
  late Directory tempDir;
  final messages = <String>[];
  final dnaCalls = <List<String>>[];

  void ggLog(String message) => messages.add(rmControls(message));

  File file(String rel) => File(path.join(tempDir.path, rel));

  /// Stands in for `gg dna init/add/build`: leaves what a real run leaves
  /// in [root] — the pub scaffold with the resolved [version] in the lock,
  /// the managed CLAUDE.md block and one skill.
  RunDna fakeDna(String root, {String version = '0.5.1'}) => (args) async {
    dnaCalls.add(args);
    switch (args.first) {
      case 'init':
        File(path.join(root, 'pubspec.yaml')).writeAsStringSync('name: ws\n');
      case 'add':
        File(path.join(root, 'pubspec.lock')).writeAsStringSync(
          'packages:\n'
          '  dna_gg:\n'
          '    dependency: "direct dev"\n'
          '    version: "$version"\n',
        );
        Directory(path.join(root, '.dart_tool')).createSync();
      case 'build':
        File(path.join(root, 'CLAUDE.md')).writeAsStringSync('$_block\n');
        File(path.join(root, '.claude', 'skills', 'gg', 'SKILL.md'))
          ..createSync(recursive: true)
          ..writeAsStringSync('# gg $version\n');
    }
  };

  setUp(() {
    messages.clear();
    dnaCalls.clear();
    tempDir = Directory.systemTemp.createTempSync('workspace_dna_test_');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  group('instantiateWorkspaceDna', () {
    test(
      'runs init, add, build and keeps only .claude and CLAUDE.md',
      () async {
        await instantiateWorkspaceDna(
          root: tempDir.path,
          runDna: fakeDna(tempDir.path),
          ggLog: ggLog,
        );

        final root = tempDir.path.replaceAll(r'\', '/');
        expect(dnaCalls, [
          ['init', '--target', root, '--language', 'dart'],
          [
            'add',
            workspaceDnaLayer,
            '--target',
            root,
            '--workspace',
            '--quiet',
          ],
          ['build', '--target', root, '--workspace', '--quiet'],
        ]);
        expect(file('pubspec.yaml').existsSync(), isFalse);
        expect(file('pubspec.lock').existsSync(), isFalse);
        expect(Directory(file('.dart_tool').path).existsSync(), isFalse);
        expect(file('CLAUDE.md').existsSync(), isTrue);
        expect(messages.last, '✓ dna_gg instantiated in the workspace');
      },
    );

    test('stamps the version the lock resolved', () async {
      await instantiateWorkspaceDna(
        root: tempDir.path,
        runDna: fakeDna(tempDir.path, version: '0.7.0'),
        ggLog: ggLog,
      );
      expect(file(dnaVersionStampPath).readAsStringSync(), '0.7.0');
    });

    test('writes no stamp without a lock or a dna_gg entry in it', () async {
      // No lock at all.
      await instantiateWorkspaceDna(
        root: tempDir.path,
        runDna: (_) async {},
        ggLog: ggLog,
      );
      expect(file(dnaVersionStampPath).existsSync(), isFalse);

      // A lock that does not name dna_gg.
      await instantiateWorkspaceDna(
        root: tempDir.path,
        runDna: (args) async {
          if (args.first == 'add') {
            file('pubspec.lock').writeAsStringSync('packages:\n  other: {}\n');
          }
        },
        ggLog: ggLog,
      );
      expect(file(dnaVersionStampPath).existsSync(), isFalse);
    });

    test(
      'reports a failure with the manual steps and keeps the scaffold',
      () async {
        await instantiateWorkspaceDna(
          root: tempDir.path,
          runDna: (args) async {
            if (args.first == 'init') {
              file('pubspec.yaml').writeAsStringSync('name: ws\n');
              return;
            }
            throw Exception('pub add failed');
          },
          ggLog: ggLog,
        );
        expect(file('pubspec.yaml').existsSync(), isTrue);
        expect(
          messages,
          contains('Could not instantiate dna_gg: Exception: pub add failed'),
        );
        expect(messages.last, contains('gg dna build --workspace'));
      },
    );
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
          runDna: fakeDna(tempDir.path, version: version),
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

    test('helixSelectPrompt asks through the gg prompts', () async {
      final prompts = _RecordingPrompts();
      GgPrompts.current = prompts;
      addTearDown(() => GgPrompts.current = null);

      final index = await helixSelectPrompt(
        prompt: 'Which language?',
        options: ['Dart', 'TypeScript'],
      );
      expect(index, 1);
      expect(prompts.prompt, 'Which language?');
      expect(prompts.options, ['Dart', 'TypeScript']);
    });
  });
}
