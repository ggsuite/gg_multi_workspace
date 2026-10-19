// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_create_repo/gg_create_repo.dart';
import 'package:gg_multi_workspace/src/backend/workspace_repo_host.dart';
import 'package:gg_multi_workspace/src/commands/do/create.dart';
import 'package:gg_multi_workspace/src/commands/do/create/repo.dart';
import 'package:gg_one/gg_one.dart' show GgPrompts;
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late String inTicket;

  setUpAll(() {
    registerFallbackValue(const RepoOptions());
    registerFallbackValue(RepoSpec.example());
    registerFallbackValue(StandaloneHost(outputDir: Directory.systemTemp));
  });

  setUp(() {
    root = Directory.systemTemp.createTempSync('repo_command_');
    inTicket = p.join(root.path, 'ticket');
    Directory(p.join(root.path, '.ocean', 'ggsuite'))
        .createSync(recursive: true);
    File(p.join(inTicket, 'ticket.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{}');
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('RepoCommand', () {
    test('is »gg do create repo« with an --add flag', () {
      final command = RepoCommand.example();
      expect(command.name, 'repo');
      expect(command.description, contains('ticket'));
      expect(command.argParser.options['add']!.defaultsTo, true);
      command.ggLog('logs nowhere by default');
      expect(
        CreateCommand(ggLog: (_) {}).subcommands['repo'],
        isA<RepoCommand>(),
      );
    });

    // #########################################################################
    test('plans with the host of the folder it runs in', () async {
      final messages = <String>[];
      final collector = MockSpecCollector();
      final preflight = MockPreflight();
      when(
        () => collector.collect(
          any<RepoOptions>(),
          any<RepoHost>(),
          earlier: any(named: 'earlier'),
        ),
      ).thenAnswer(
        (_) async => (spec: RepoSpec.example(name: 'gg_new'), asked: false),
      );
      when(
        () => preflight.run(
          any<RepoSpec>(),
          any<RepoHost>(),
          resumes: any(named: 'resumes'),
        ),
      ).thenAnswer((_) async => []);
      final command = RepoCommand.example(
        ggLog: (m) => messages.add(rmConsoleColors(m)),
        executionPath: inTicket,
        collector: collector,
        preflight: preflight,
      );

      await (CommandRunner<dynamic>(
        'gg',
        'gg',
      )..addCommand(command)).run(['repo', '--dry-run']);

      final log = messages.join('\n');
      expect(log, contains(p.join('.ocean', 'ggsuite', 'gg_new')));
      expect(log, contains('add it to the ticket ticket'));
    });

    // #########################################################################
    test('asks with the prompts it is given before creating', () async {
      final messages = <String>[];
      final collector = MockSpecCollector();
      final preflight = MockPreflight();
      final prompts = _Prompts();
      when(
        () => collector.collect(
          any<RepoOptions>(),
          any<RepoHost>(),
          earlier: any(named: 'earlier'),
        ),
      ).thenAnswer(
        (_) async => (spec: RepoSpec.example(name: 'gg_new'), asked: true),
      );
      when(
        () => preflight.run(
          any<RepoSpec>(),
          any<RepoHost>(),
          resumes: any(named: 'resumes'),
        ),
      ).thenAnswer((_) async => []);
      final command = RepoCommand.example(
        ggLog: (m) => messages.add(rmConsoleColors(m)),
        executionPath: inTicket,
        collector: collector,
        preflight: preflight,
        prompts: prompts,
      );

      await (CommandRunner<dynamic>(
        'gg',
        'gg',
      )..addCommand(command)).run(['repo']);

      expect(prompts.asked, ['Create ggsuite/gg_new?']);
      expect(messages.last, 'Nothing was created.');
    });

    // #########################################################################
    group('hostFor()', () {
      test('is the workspace host inside a workspace', () {
        final args = RepoCommand.example().argParser.parse(['--no-add']);

        final host = RepoCommand.hostFor(args, executionPath: inTicket);

        expect(host, isA<WorkspaceRepoHost>());
        host as WorkspaceRepoHost;
        expect(host.addToTicket, false);
        expect(p.equals(host.oceanPath, p.join(root.path, '.ocean')), true);
        expect(host.executionPath, inTicket);
      });

      test('rejects --output inside a workspace', () {
        final args = RepoCommand.example().argParser.parse(['-o', root.path]);

        expect(
          () => RepoCommand.hostFor(args, executionPath: inTicket),
          throwsA(
            isA<Exception>().having(
              (e) => rmConsoleColors(e.toString()),
              'message',
              contains('--output is only for use outside of a workspace'),
            ),
          ),
        );
      });

      test('is the standalone host outside of a workspace', () {
        final outside = Directory.systemTemp.createTempSync('outside_');
        addTearDown(() => outside.deleteSync(recursive: true));
        final args = RepoCommand.example().argParser.parse([
          '-o',
          outside.path,
        ]);

        final host = RepoCommand.hostFor(args, executionPath: outside.path);

        expect(host, isA<StandaloneHost>());
        expect(
          (host as StandaloneHost).outputDir.path,
          p.normalize(p.absolute(outside.path)),
        );
      });
    });
  });
}

/// Answers every question with no and records it; no terminal in tests.
class _Prompts extends GgPrompts {
  final asked = <String>[];

  @override
  Future<int> select({
    required String prompt,
    required List<String> options,
    int initialIndex = 0,
  }) async {
    asked.add(prompt);
    return options.length - 1;
  }

  @override
  Future<String> input({
    required String prompt,
    String? defaultValue,
    String? initialText,
    bool asMessageEditor = false,
  }) async => fail('asks no text');
}
