// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_multi_workspace/src/commands/do/create/graph.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('GraphCommand', () {
    late Directory tempDir;
    late CommandRunner<void> runner;
    final messages = <String>[];

    void ggLog(String msg) {
      messages.add(rmControls(msg));
    }

    /// Writes a Dart package into `<root>/<org>/<name>`.
    void writePackage({
      required String root,
      required String org,
      required String name,
      List<String> dependencies = const <String>[],
      List<String> devDependencies = const <String>[],
    }) {
      final dir = Directory(p.join(tempDir.path, root, org, name))
        ..createSync(recursive: true);

      final buffer = StringBuffer('name: $name\nversion: 1.0.0\n');
      if (dependencies.isNotEmpty) {
        buffer.writeln('dependencies:');
        for (final dep in dependencies) {
          buffer.writeln('  $dep: ^1.0.0');
        }
      }
      if (devDependencies.isNotEmpty) {
        buffer.writeln('dev_dependencies:');
        for (final dep in devDependencies) {
          buffer.writeln('  $dep: ^1.0.0');
        }
      }

      File(p.join(dir.path, 'pubspec.yaml'))
          .writeAsStringSync(buffer.toString());
    }

    /// The single message the command wrote to stdout.
    String output() {
      expect(messages, hasLength(1));
      return messages.single;
    }

    /// All edges of the mermaid output as `from arrow to`.
    List<String> mermaidEdges() => output()
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.contains('-->') || l.contains('-.->'))
        .toList();

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync('graph_test_');
      runner = CommandRunner<void>('test', 'GraphCommand Test')
        ..addCommand(GraphCommand(ggLog: ggLog));

      // The ocean: `a` depends on `b` and - redundantly - on `c`,
      // `b` depends on `c`. `a` also has a dev dependency on `d` and a third
      // party dependency that is no local repository.
      writePackage(
        root: '.ocean',
        org: 'org_a',
        name: 'a',
        dependencies: <String>['b', 'c', 'external_pkg'],
        devDependencies: <String>['d'],
      );
      writePackage(
        root: '.ocean',
        org: 'org_a',
        name: 'b',
        dependencies: <String>['c'],
      );
      writePackage(root: '.ocean', org: 'org_a', name: 'c');
      writePackage(root: '.ocean', org: 'org_a', name: 'd');

      // A second organization, only reachable via `--org`.
      writePackage(root: '.ocean', org: 'org_b', name: 'e');

      // A TypeScript repo depending on two npm packages whose names collapse
      // to the same mermaid node id.
      final ts = Directory(p.join(tempDir.path, '.ocean', 'org_a', 'ts_pkg'))
        ..createSync(recursive: true);
      File(p.join(ts.path, 'package.json')).writeAsStringSync(
        jsonEncode(<String, dynamic>{
          'name': 'ts_pkg',
          'version': '1.0.0',
          'dependencies': <String, String>{
            '@scope/pkg': '^1.0.0',
            '_scope_pkg': '^1.0.0',
          },
        }),
      );

      // A ticket that has `b` checked out.
      writePackage(
        root: p.join('tickets', '1'),
        org: 'org_a',
        name: 'b',
        dependencies: <String>['c'],
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    Future<void> run(String workingDir, [List<String> args = const []]) =>
        runner.run(<String>['graph', '--input', workingDir, ...args]);

    String oceanDir() => tempDir.path;
    String ticketDir() => p.join(tempDir.path, 'tickets', '1');

    group('outside a ticket', () {
      test('graphs the whole ocean', () async {
        await run(oceanDir(), <String>['--no-transitive-reduction']);

        expect(output(), startsWith('flowchart LR'));
        expect(output(), contains('a["a"]'));
        expect(output(), contains('e["e"]'));
        expect(mermaidEdges(), contains('b --> a'));
        expect(mermaidEdges(), contains('c --> a'));
        expect(mermaidEdges(), contains('c --> b'));
      });

      test('--org narrows the graph down to one organization', () async {
        await run(oceanDir(), <String>['--org', 'org_b']);

        expect(output(), contains('e["e"]'));
        expect(output(), isNot(contains('a["a"]')));
      });

      test('--org throws for an unknown organization', () async {
        await expectLater(
          run(oceanDir(), <String>['--org', 'nope']),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              contains('nope'),
            ),
          ),
        );
      });
    });

    group('inside a ticket', () {
      test('graphs the ticket repos and what they reach', () async {
        await run(ticketDir());

        // `b` is checked out and reaches `c`. `a` depends on `b`, but is not
        // reachable from it, so it stays out.
        expect(output(), contains('b["b"]'));
        expect(output(), contains('c["c"]'));
        expect(output(), isNot(contains('a["a"]')));
        expect(output(), contains('class b ticket;'));
      });

      test('takes the checked out repo instead of the ocean one', () async {
        await run(ticketDir(), <String>['--format=json']);

        final json = jsonDecode(output()) as Map<String, dynamic>;
        final nodes = (json['nodes'] as List).cast<Map<String, dynamic>>();
        final b = nodes.firstWhere((n) => n['name'] == 'b');
        expect(b['inTicket'], isTrue);
        expect(b['path'], p.join('org_a', 'b'));

        final c = nodes.firstWhere((n) => n['name'] == 'c');
        expect(c['inTicket'], isFalse);
      });
    });

    group('--transitive-reduction', () {
      test('hides the edge that a longer path already implies', () async {
        await run(oceanDir());

        expect(mermaidEdges(), contains('b --> a'));
        expect(mermaidEdges(), contains('c --> b'));
        expect(mermaidEdges(), isNot(contains('c --> a')));
      });

      test('--no-transitive-reduction keeps it', () async {
        await run(oceanDir(), <String>['--no-transitive-reduction']);

        expect(mermaidEdges(), contains('c --> a'));
      });
    });

    group('--dev-dependencies', () {
      test('shows dev dependencies as dashed edges by default', () async {
        await run(oceanDir());

        expect(mermaidEdges(), contains('d -.-> a'));
      });

      test('--no-dev-dependencies drops them', () async {
        await run(oceanDir(), <String>['--no-dev-dependencies']);

        // `d` stays a node of the workspace, but the edge to it is gone.
        expect(output(), contains('d["d"]'));
        expect(output(), isNot(contains('-.->')));
      });
    });

    group('--3rdparty-deps', () {
      test('are hidden by default', () async {
        await run(oceanDir());

        expect(output(), isNot(contains('external_pkg')));
      });

      test('are shown when requested', () async {
        await run(oceanDir(), <String>['--3rdparty-deps']);

        expect(mermaidEdges(), contains('external_pkg --> a'));
        expect(
          output(),
          contains('class _scope_pkg,_scope_pkg_2,external_pkg external;'),
        );
      });

      test('get a unique id even when their names collapse', () async {
        await run(oceanDir(), <String>['--3rdparty-deps']);

        // `@scope/pkg` and `_scope_pkg` both sanitize to `_scope_pkg`.
        expect(output(), contains('_scope_pkg["@scope/pkg"]'));
        expect(output(), contains('_scope_pkg_2["_scope_pkg"]'));
        expect(mermaidEdges(), contains('_scope_pkg --> ts_pkg'));
        expect(mermaidEdges(), contains('_scope_pkg_2 --> ts_pkg'));
      });

      test('are marked as external in json', () async {
        await run(oceanDir(), <String>['--3rdparty-deps', '--format=json']);

        final json = jsonDecode(output()) as Map<String, dynamic>;
        final nodes = (json['nodes'] as List).cast<Map<String, dynamic>>();
        final external = nodes.firstWhere((n) => n['name'] == 'external_pkg');
        expect(external['external'], isTrue);
        expect(external.containsKey('path'), isFalse);
      });
    });

    group('edge direction', () {
      test('points from the dependency to the dependent', () async {
        await run(oceanDir());

        // `a` depends on `b`, so the arrow leaves `b`: in a `LR` flowchart the
        // dependencies end up left of the packages that need them.
        expect(mermaidEdges(), contains('b --> a'));
        expect(mermaidEdges(), isNot(contains('a --> b')));
      });

      test('json carries the same direction as the arrows', () async {
        await run(oceanDir(), <String>['--format=json']);

        final json = jsonDecode(output()) as Map<String, dynamic>;
        final edges = (json['edges'] as List).cast<Map<String, dynamic>>();
        final ab = edges.firstWhere((e) => e['from'] == 'b' && e['to'] == 'a');
        expect(ab['dev'], isFalse);
        expect(edges.any((e) => e['from'] == 'a' && e['to'] == 'b'), isFalse);
      });
    });

    group('--output', () {
      test('writes the graph to the file instead of stdout', () async {
        final target = p.join(tempDir.path, 'out', 'graph.mmd');

        await run(oceanDir(), <String>['--output', target]);

        final file = File(target);
        expect(file.existsSync(), isTrue);
        final content = file.readAsStringSync();
        expect(content, startsWith('flowchart LR'));
        expect(content, endsWith('\n'));
        expect(content, contains('b --> a'));

        // Only the confirmation goes to stdout, not the graph.
        expect(output(), contains('Wrote graph to'));
        expect(output(), contains(target));
        expect(output(), isNot(contains('flowchart')));
      });

      test('creates missing parent directories', () async {
        final target = p.join(tempDir.path, 'deeply', 'nested', 'graph.json');

        await run(oceanDir(), <String>['--format=json', '-o', target]);

        final content = File(target).readAsStringSync();
        expect(jsonDecode(content), isA<Map<String, dynamic>>());
      });

      test('overwrites an existing file', () async {
        final target = p.join(tempDir.path, 'graph.mmd');
        File(target).writeAsStringSync('stale content');

        await run(oceanDir(), <String>['--output', target]);

        expect(File(target).readAsStringSync(), isNot(contains('stale')));
      });
    });

    group('--group-by-orgs', () {
      test('boxes the repositories per organization by default', () async {
        await run(oceanDir());

        expect(output(), contains('subgraph org_org_a["org_a"]'));
        expect(output(), contains('subgraph org_org_b["org_b"]'));

        // The nodes sit inside their box, the edges outside.
        final lines = output().split('\n');
        final orgA = lines.indexOf('  subgraph org_org_a["org_a"]');
        final end = lines.indexOf('  end', orgA);
        expect(lines.sublist(orgA, end), contains('    a["a"]'));
        expect(lines.sublist(orgA, end), isNot(contains('    e["e"]')));
      });

      test('--no-group-by-orgs keeps the flat list', () async {
        await run(oceanDir(), <String>['--no-group-by-orgs']);

        expect(output(), isNot(contains('subgraph')));
        expect(output(), contains('  a["a"]'));
        expect(mermaidEdges(), contains('b --> a'));
      });

      test('does not box a single organization', () async {
        await run(oceanDir(), <String>['--org', 'org_a']);

        expect(output(), isNot(contains('subgraph')));
        expect(output(), contains('a["a"]'));
      });

      test('leaves third party packages outside the boxes', () async {
        await run(oceanDir(), <String>['--3rdparty-deps']);

        final lines = output().split('\n');
        expect(lines, contains('  external_pkg["external_pkg"]'));
        expect(lines, isNot(contains('    external_pkg["external_pkg"]')));
      });

      test('gives an org a subgraph id that no node uses', () async {
        // Mermaid keeps subgraph and node ids in one namespace. An
        // organization `a` would produce the id `org_a`, which the package of
        // that name already occupies.
        writePackage(root: '.ocean', org: 'org_b', name: 'org_a');
        writePackage(root: '.ocean', org: 'a', name: 'inside_a');

        await run(oceanDir());

        expect(output(), contains('  org_a["org_a"]'));
        expect(output(), contains('subgraph org_a_2["a"]'));
      });

      test('is ignored by the json format', () async {
        await run(oceanDir(), <String>['--format=json']);

        final json = jsonDecode(output()) as Map<String, dynamic>;
        final nodes = (json['nodes'] as List).cast<Map<String, dynamic>>();
        final a = nodes.firstWhere((n) => n['name'] == 'a');
        expect(a['organization'], 'org_a');
      });
    });

    group('--orientation', () {
      test('is horizontal by default', () async {
        await run(oceanDir());
        expect(output(), startsWith('flowchart LR'));
      });

      test('vertical renders top down', () async {
        await run(oceanDir(), <String>['--orientation=vertical']);
        expect(output(), startsWith('flowchart TD'));
      });
    });

    group('--format=json', () {
      test('writes a deterministically sorted document', () async {
        await run(oceanDir(), <String>['--format=json']);

        final json = jsonDecode(output()) as Map<String, dynamic>;
        expect(json['orientation'], 'horizontal');
        expect(json['transitiveReduction'], isTrue);

        final nodes = (json['nodes'] as List).cast<Map<String, dynamic>>();
        final names = nodes.map((n) => n['name'] as String).toList();
        expect(names, <String>['a', 'b', 'c', 'd', 'e', 'ts_pkg']);
        expect(nodes.first['language'], 'dart');
        expect(nodes.first['organization'], 'org_a');

        final edges = (json['edges'] as List)
            .cast<Map<String, dynamic>>()
            .map((e) => '${e['from']}->${e['to']} dev:${e['dev']}')
            .toList();
        // `from` is the package being depended upon, `to` the one that needs
        // it - the same direction the mermaid arrows are drawn in.
        expect(edges, <String>[
          'b->a dev:false',
          'c->b dev:false',
          'd->a dev:true',
        ]);
      });
    });

    test('throws when the workspace holds no repositories', () async {
      final empty = Directory.systemTemp.createTempSync('graph_empty_');
      Directory(p.join(empty.path, '.ocean')).createSync();
      try {
        await expectLater(run(empty.path), throwsA(isA<UsageException>()));
      } finally {
        empty.deleteSync(recursive: true);
      }
    });
  });
}
