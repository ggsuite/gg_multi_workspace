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
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Returns a fixed spec without asking.
class _Collector extends SpecCollector {
  _Collector() : super(ggLog: (_) {});

  @override
  Future<RepoSpec> collect(RepoOptions options, RepoHost host) async =>
      RepoSpec.example(name: 'gg_new');
}

/// Finds nothing.
class _Preflight extends Preflight {
  @override
  Future<List<Finding>> run(RepoSpec spec, RepoHost host) async => [];
}

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('repo_command_');
    Directory(p.join(root.path, '.ocean', 'ggsuite'))
        .createSync(recursive: true);
    File(p.join(root.path, 'ticket', 'ticket.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{}');
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('RepoCommand', () {
    test('is »gg do create repo« with an --add flag', () {
      final command = RepoCommand(ggLog: (_) {});
      expect(command.name, 'repo');
      expect(command.description, contains('ticket'));
      expect(command.argParser.options['add']!.defaultsTo, true);
      expect(
        CreateCommand(ggLog: (_) {}).subcommands['repo'],
        isA<RepoCommand>(),
      );
    });

    // #########################################################################
    test('plans with the host of the folder it runs in', () async {
      final messages = <String>[];
      final command = RepoCommand(
        ggLog: (m) => messages.add(rmConsoleColors(m)),
        executionPath: p.join(root.path, 'ticket'),
        collector: _Collector(),
        preflight: _Preflight(),
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
    group('hostFor()', () {
      test('is the workspace host inside a workspace', () {
        final command = RepoCommand(ggLog: (_) {});
        final args = command.argParser.parse(['--no-add']);
        final inTicket = p.join(root.path, 'ticket');

        final host = RepoCommand.hostFor(args, executionPath: inTicket);

        expect(host, isA<WorkspaceRepoHost>());
        host as WorkspaceRepoHost;
        expect(host.addToTicket, false);
        expect(p.equals(host.oceanPath, p.join(root.path, '.ocean')), true);
        expect(host.executionPath, inTicket);
      });

      test('is the standalone host outside of a workspace', () {
        final outside = Directory.systemTemp.createTempSync('outside_');
        addTearDown(() => outside.deleteSync(recursive: true));
        final command = RepoCommand(ggLog: (_) {});
        final args = command.argParser.parse(['-o', outside.path]);

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
