// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_multi_core/gg_multi_core.dart';
import 'package:gg_multi_workspace/src/commands/do/localize.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late Directory ticketDir;
  late List<String> messages;
  late List<String> installs;

  Future<String> git(Directory dir, List<String> args) async {
    final result = await Process.run('git', args, workingDirectory: dir.path);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return '${result.stdout}'.trim();
  }

  Future<Directory> repo(String name, String deps) async {
    final dir = Directory(path.join(ticketDir.path, name))..createSync();
    File(path.join(dir.path, 'pubspec.yaml')).writeAsStringSync(
      'name: $name\nversion: 1.0.0\n'
      'environment:\n  sdk: ^3.0.0\n$deps',
    );
    // gg commits only with git's EOL conversion on.
    File(path.join(dir.path, '.gitattributes'))
        .writeAsStringSync('* text=auto eol=lf\n');
    await git(dir, ['init', '-b', 'main']);
    await git(dir, ['config', 'user.email', 'test@example.com']);
    await git(dir, ['config', 'user.name', 'Test']);
    await git(dir, ['add', '.']);
    await git(dir, ['commit', '-m', 'Initial commit']);
    await git(dir, ['checkout', '-b', 'T1']);
    return dir;
  }

  Future<void> run() async {
    final localizer = TicketLocalizer(
      ggLog: messages.add,
      processRunner:
          (
            executable,
            arguments, {
            workingDirectory,
            runInShell = false,
            environment,
          }) async {
            installs.add('${path.basename(workingDirectory!)}: $executable');
            return ProcessResult(0, 0, '', '');
          },
    );
    final runner = CommandRunner<void>('test', 'test')
      ..addCommand(
        DoLocalizeCommand(
          ggLog: (m) => messages.add(rmControls(m)),
          ticketLocalizer: localizer,
        ),
      );
    await runner.run(['localize', '--input', ticketDir.path]);
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('do_localize_test');
    ticketDir = Directory(path.join(tmp.path, 'T1'))..createSync();
    File(path.join(ticketDir.path, 'ticket.json'))
        .writeAsStringSync('{"issue_id": "T1"}');
    messages = <String>[];
    installs = <String>[];
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('DoLocalizeCommand', () {
    test('localizes and commits a dependency added by hand', () async {
      final a = await repo('a', '');
      await repo('b', '');

      // The user adds b to a by hand, without committing it.
      final pubspec = File(path.join(a.path, 'pubspec.yaml'));
      pubspec.writeAsStringSync(
        '${pubspec.readAsStringSync()}dependencies:\n  b: ^1.0.0\n',
      );

      await run();

      final overrides = File(path.join(a.path, 'pubspec_overrides.yaml'));
      expect(overrides.readAsStringSync(), contains('path: ../b'));
      expect(installs, ['a: dart']);
      expect(messages, ['✓ Localized the references of a']);

      // gg's override is committed, the user's manifest edit is not.
      expect(
        await git(a, ['log', '-1', '--format=%s']),
        '#gg: changed references to path',
      );
      expect(await git(a, ['status', '--porcelain']), 'M pubspec.yaml');

      // A second run finds nothing to do.
      messages.clear();
      await run();
      expect(messages, contains('✓ All references are already localized.'));
    });

    test('localizes and only warns about missing repos', () async {
      // a reaches its ticket sibling d only through the ocean's c.
      final a = await repo('a', 'dependencies:\n  b: ^1.0.0\n  c: ^1.0.0\n');
      await repo('b', '');
      await repo('d', '');
      final c = Directory(path.join(tmp.path, '.ocean', 'org', 'c'))
        ..createSync(recursive: true);
      File(path.join(c.path, 'pubspec.yaml')).writeAsStringSync(
        'name: c\nversion: 1.0.0\ndependencies:\n  d: ^1.0.0\n',
      );

      await run();

      expect(messages, [
        '✓ Localized the references of a',
        '\n⚠️ Repos between the ticket repos, but not in it:',
        '  - c',
        'Run gg do add c to add them.\n',
      ]);
      expect(
        File(path.join(a.path, 'pubspec_overrides.yaml')).readAsStringSync(),
        contains('path: ../b'),
      );
    });

    test('warns about a ticket without repos', () async {
      await run();
      expect(messages, contains('⚠️ No repos in this ticket'));
    });

    test('refuses to run outside a ticket', () async {
      final runner = CommandRunner<void>('test', 'test')
        ..addCommand(DoLocalizeCommand(ggLog: messages.add));
      await expectLater(
        runner.run(['localize', '--input', tmp.path]),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            'gg do localize only works inside a ticket folder.',
          ),
        ),
      );
    });
  });
}
