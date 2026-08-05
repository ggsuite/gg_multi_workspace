// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as p;

import 'package:gg_multi_core/gg_multi_core.dart';

/// One directed edge of the dependency graph.
///
/// While the graph is built the edge runs along "depends on" ([from] needs
/// [to]). For the output it is reversed, so that [from] is the package being
/// depended upon and [to] the one that needs it - see `_toMermaid`.
class GraphEdge {
  /// Creates an edge from [from] to [to].
  GraphEdge({required this.from, required this.to, required this.dev});

  /// Name of the package the arrow starts at.
  final String from;

  /// Name of the package the arrow points at.
  final String to;

  /// True when the edge is only declared as a dev dependency.
  final bool dev;
}

/// One node of the dependency graph.
class GraphNode {
  /// Creates a node.
  GraphNode({
    required this.name,
    required this.path,
    required this.language,
    required this.organization,
    required this.external,
    required this.inTicket,
  });

  /// Package name.
  final String name;

  /// Location relative to the workspace root, i.e. `<org>/<repo>` or `<repo>`.
  /// Null for a third party package that is not checked out locally.
  final String? path;

  /// `dart`, `typescript` or `dart+typescript`. Null for third party packages.
  final String? language;

  /// Organization folder the repository lives in, if any.
  final String? organization;

  /// True when the package is not one of the local repositories.
  final bool external;

  /// True when the repository is checked out into the current ticket.
  final bool inTicket;
}

/// Writes the dependency graph of the current workspace to stdout.
///
/// Inside a ticket the graph covers the repositories of that ticket plus the
/// repositories they depend on in the ocean. Outside a ticket it
/// covers the whole ocean. `--org` narrows it down to a single
/// organization.
/// `--no-group-by-orgs` turns the organization boxes off. They only appear
/// when more than one organization is shown — one box around everything is
/// noise — and the flag is mermaid-only.
class GraphCommand extends DirCommand<void> {
  /// Constructor
  GraphCommand({
    required super.ggLog,
    super.name = 'graph',
    super.description = 'Write the dependency graph to stdout or a file',
    Graph? graph,
  }) : _graph = graph ?? Graph(ggLog: _warn) {
    _addArgs();
  }

  /// Builds the dependency graph of a set of package folders.
  final Graph _graph;

  @override
  Future<void> exec({required Directory directory, required GgLog ggLog}) =>
      get(directory: directory, ggLog: ggLog);

  @override
  Future<void> get({required Directory directory, required GgLog ggLog}) async {
    final format = argResults!['format'] as String;
    final orientation = argResults!['orientation'] as String;
    final reduce = argResults!['transitive-reduction'] as bool;
    final withDevDeps = argResults!['dev-dependencies'] as bool;
    final with3rdParty = argResults!['3rdparty-deps'] as bool;
    final org = argResults!['org'] as String?;

    final root = p.absolute(directory.path);
    final oceanPath = WorkspaceUtils.defaultOceanWorkspacePath(
      workingDir: root,
    );
    final ticketPath = WorkspaceUtils.detectTicketPath(root);

    // Collect the repository folders the graph is built from. Inside a ticket
    // the checked out repos come first: they shadow the ocean version of the
    // same repo, while the remaining ocean repos stay available so that
    // dependencies pointing outside the ticket can still be resolved.
    final oceanDirs = RepoFolderResolver.repoDirs(oceanPath);
    final ticketDirs = ticketPath == null
        ? const <Directory>[]
        : RepoFolderResolver.repoDirs(ticketPath);
    final ticketNames = ticketDirs.map((d) => p.basename(d.path)).toSet();

    var dirs = <Directory>[
      ...ticketDirs,
      ...oceanDirs.where((d) => !ticketNames.contains(p.basename(d.path))),
    ];

    if (org != null) {
      dirs = dirs
          .where((d) => p.basename(d.parent.path) == org)
          .toList(growable: false);
      if (dirs.isEmpty) {
        throw UsageException(
          'No repositories found for organization "$org".',
          usage,
        );
      }
    }

    if (dirs.isEmpty) {
      throw UsageException('No repositories found in the workspace.', usage);
    }

    // Build the dependency graph. Warnings about duplicate packages go to
    // stderr so that stdout stays machine readable.
    final roots = await _graph.get(
      directory: Directory(oceanPath),
      ggLog: _warn,
      packageDirs: dirs,
    );

    final packages = _collectNodes(roots);

    // Every alias (dart name, npm name, folder name) points at its package, so
    // a dependency declared under any of them resolves to the same node.
    final byAlias = <String, Node>{};
    for (final node in packages.values) {
      for (final alias in node.aliases) {
        byAlias[alias] = node;
      }
    }

    final edges = _buildEdges(
      packages: packages,
      byAlias: byAlias,
      withDevDeps: withDevDeps,
      with3rdParty: with3rdParty,
    );

    final externalNames = <String>{
      for (final edge in edges.values)
        if (!packages.containsKey(edge.to)) edge.to,
    };

    var names = <String>{...packages.keys, ...externalNames};
    var visibleEdges = edges.values.toList();

    // In a ticket only the part of the graph the ticket repos actually reach
    // is interesting - the rest of the ocean is not involved.
    if (ticketPath != null) {
      final ticketPackages = packages.values
          .where((n) => ticketNames.contains(p.basename(n.directory.path)))
          .map((n) => n.name);
      names = _reachableFrom(ticketPackages, visibleEdges);
      visibleEdges = visibleEdges
          .where((e) => names.contains(e.from) && names.contains(e.to))
          .toList();
    }

    if (reduce) {
      visibleEdges = _transitiveReduction(visibleEdges);
    }

    final graphNodes = _describeNodes(
      names: names,
      packages: packages,
      oceanPath: oceanPath,
      ticketPath: ticketPath,
      ticketNames: ticketNames,
    );

    // Everything above works along "depends on". The graph is drawn the other
    // way round - the arrow leaves the package that is depended upon and points
    // at the one that needs it - so that a `LR` flowchart puts the dependencies
    // on the left, the dependents on the right, and reads along the build
    // order. Reversing here keeps both output formats consistent.
    final drawnEdges =
        <GraphEdge>[
          for (final edge in visibleEdges)
            GraphEdge(from: edge.to, to: edge.from, dev: edge.dev),
        ]..sort((a, b) {
          final byFrom = a.from.compareTo(b.from);
          return byFrom != 0 ? byFrom : a.to.compareTo(b.to);
        });

    final rendered = format == 'json'
        ? _toJson(
            nodes: graphNodes,
            edges: drawnEdges,
            orientation: orientation,
            transitiveReduction: reduce,
          )
        : _toMermaid(
            nodes: graphNodes,
            edges: drawnEdges,
            orientation: orientation,
            groupByOrgs: argResults!['group-by-orgs'] as bool,
          );

    final output = argResults!['output'] as String?;
    if (output == null) {
      ggLog(rendered);
      return;
    }

    final file = File(p.absolute(output));
    await file.parent.create(recursive: true);
    await file.writeAsString('$rendered\n');
    ggLog('✓ Wrote graph to ${file.path}');
  }

  // ######################
  // Private
  // ######################

  // ...........................................................................
  void _addArgs() {
    argParser
      ..addOption(
        'format',
        allowed: <String>['mermaid', 'json'],
        defaultsTo: 'mermaid',
        help: 'The output format of the graph.',
      )
      ..addOption(
        'orientation',
        allowed: <String>['horizontal', 'vertical'],
        defaultsTo: 'horizontal',
        help: 'Layout direction of the mermaid graph.',
      )
      ..addFlag(
        'transitive-reduction',
        defaultsTo: true,
        help: 'Hide edges that are already implied by a longer path.',
      )
      ..addFlag(
        'dev-dependencies',
        defaultsTo: true,
        help: 'Include dev dependencies as edges.',
      )
      ..addFlag(
        '3rdparty-deps',
        defaultsTo: false,
        help: 'Include dependencies that are no local repositories.',
      )
      ..addFlag(
        'group-by-orgs',
        defaultsTo: true,
        help: 'Box the repos of each organization (default)',
      )
      ..addOption(
        'org',
        help: 'Only graph the repositories of this organization.',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Write the graph to this file instead of stdout.',
      );
  }

  // ...........................................................................
  /// Writes graph warnings to stderr, keeping stdout free for the graph.
  // coverage:ignore-start
  static void _warn(String message) => stderr.writeln(message);
  // coverage:ignore-end

  // ...........................................................................
  /// Returns all nodes of the graph, not only the roots.
  Map<String, Node> _collectNodes(Map<String, Node> roots) {
    final result = <String, Node>{};

    void visit(Node node) {
      if (result.containsKey(node.name)) {
        return;
      }
      result[node.name] = node;
      for (final dependency in node.dependencies.values) {
        visit(dependency);
      }
    }

    for (final root in roots.values) {
      visit(root);
    }

    return result;
  }

  // ...........................................................................
  /// Builds the edges from the manifests, keyed by `<from>-><to>`.
  ///
  /// `Graph` merges dependencies and dev dependencies into one set and drops
  /// everything that is no local package, so the edges are derived from the
  /// manifests directly.
  Map<String, GraphEdge> _buildEdges({
    required Map<String, Node> packages,
    required Map<String, Node> byAlias,
    required bool withDevDeps,
    required bool with3rdParty,
  }) {
    // `dev` per edge, so that a package reached as a dependency *and* as a dev
    // dependency - possibly through two manifests of a cross language repo -
    // is shown as the stronger of the two.
    final dev = <String, bool>{};
    final edges = <String, GraphEdge>{};

    void add(String from, String to, bool isDev) {
      if (from == to) {
        return;
      }
      final key = '$from->$to';
      dev[key] = (dev[key] ?? true) && isDev;
      edges[key] = GraphEdge(from: from, to: to, dev: dev[key]!);
    }

    for (final node in packages.values) {
      // The dependencies of every manifest the node carries. A name declared
      // as both is a regular dependency.
      final dependencies = <String, bool>{};
      for (final manifest in node.manifests) {
        if (withDevDeps) {
          for (final name in manifest.devDependencies) {
            dependencies.putIfAbsent(name, () => true);
          }
        }
        for (final name in manifest.dependencies) {
          dependencies[name] = false;
        }
      }

      for (final entry in dependencies.entries) {
        final target = byAlias[entry.key];
        if (target != null) {
          add(node.name, target.name, entry.value);
        } else if (with3rdParty) {
          add(node.name, entry.key, entry.value);
        }
      }
    }

    return edges;
  }

  // ...........................................................................
  /// Returns [starts] plus everything reachable from them along [edges].
  Set<String> _reachableFrom(Iterable<String> starts, List<GraphEdge> edges) {
    final adjacency = _adjacency(edges);
    final result = <String>{};
    final queue = <String>[...starts];

    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      if (!result.add(current)) {
        continue;
      }
      queue.addAll(adjacency[current] ?? const <String>{});
    }

    return result;
  }

  // ...........................................................................
  /// Removes every edge `u -> v` for which `v` is reachable from `u` via a
  /// path of at least two edges. The graph is acyclic: `Graph` rejects
  /// circular dependencies before we get here.
  List<GraphEdge> _transitiveReduction(List<GraphEdge> edges) {
    final adjacency = _adjacency(edges);

    bool reaches(String start, String target) {
      final seen = <String>{};
      final queue = <String>[start];
      while (queue.isNotEmpty) {
        final current = queue.removeLast();
        if (current == target) {
          return true;
        }
        if (!seen.add(current)) {
          continue;
        }
        queue.addAll(adjacency[current] ?? const <String>{});
      }
      return false;
    }

    // All removals are decided against the unreduced graph, so the result does
    // not depend on the order the edges are visited in.
    return edges.where((edge) {
      final detours = adjacency[edge.from]!.where((n) => n != edge.to);
      return !detours.any((detour) => reaches(detour, edge.to));
    }).toList();
  }

  // ...........................................................................
  Map<String, Set<String>> _adjacency(List<GraphEdge> edges) {
    final result = <String, Set<String>>{};
    for (final edge in edges) {
      (result[edge.from] ??= <String>{}).add(edge.to);
    }
    return result;
  }

  // ...........................................................................
  /// Turns the package names into the nodes that are written out.
  List<GraphNode> _describeNodes({
    required Set<String> names,
    required Map<String, Node> packages,
    required String oceanPath,
    required String? ticketPath,
    required Set<String> ticketNames,
  }) {
    final result = <GraphNode>[];

    for (final name in names.toList()..sort()) {
      final package = packages[name];
      if (package == null) {
        result.add(
          GraphNode(
            name: name,
            path: null,
            language: null,
            organization: null,
            external: true,
            inTicket: false,
          ),
        );
        continue;
      }

      final folderName = p.basename(package.directory.path);
      final inTicket =
          ticketPath != null && p.isWithin(ticketPath, package.directory.path);
      final workspacePath = inTicket ? ticketPath : oceanPath;
      final relative = RepoFolderResolver.relativePath(
        workspacePath: workspacePath,
        repoDir: package.directory,
      );
      final segments = p.split(relative);

      result.add(
        GraphNode(
          name: name,
          path: relative,
          language: _languageOf(package),
          organization: segments.length > 1 ? segments.first : null,
          external: false,
          inTicket: inTicket && ticketNames.contains(folderName),
        ),
      );
    }

    return result;
  }

  // ...........................................................................
  /// `dart`, `typescript` or `dart+typescript`.
  String _languageOf(Node node) => node.manifests
      .map((m) => m is DartPackageManifest ? 'dart' : 'typescript')
      .toSet()
      .join('+');

  // ...........................................................................
  /// Renders the graph as a mermaid flowchart.
  ///
  /// [edges] are already reversed: the arrow leaves the package that is
  /// depended upon, so `LR` puts the dependencies left and the dependents
  /// right.
  String _toMermaid({
    required List<GraphNode> nodes,
    required List<GraphEdge> edges,
    required String orientation,
    required bool groupByOrgs,
  }) {
    final ids = _mermaidIds(nodes);
    final lines = <String>[
      'flowchart ${orientation == 'vertical' ? 'TD' : 'LR'}',
    ];

    // Boxing the repositories per organization only tells the reader something
    // when there is more than one - a single box around everything is noise.
    final orgs = <String>{
      for (final node in nodes)
        if (node.organization != null) node.organization!,
    }.toList()..sort();
    final grouped = groupByOrgs && orgs.length > 1;

    if (!grouped) {
      for (final node in nodes) {
        lines.add('  ${ids[node.name]}["${node.name}"]');
      }
    } else {
      // Third party packages belong to no organization and stay outside the
      // boxes.
      for (final node in nodes.where((n) => n.organization == null)) {
        lines.add('  ${ids[node.name]}["${node.name}"]');
      }

      final orgIds = _mermaidOrgIds(orgs, ids.values);
      for (final org in orgs) {
        lines.add('  subgraph ${orgIds[org]}["$org"]');
        for (final node in nodes.where((n) => n.organization == org)) {
          lines.add('    ${ids[node.name]}["${node.name}"]');
        }
        lines.add('  end');
      }
    }

    for (final edge in edges) {
      final arrow = edge.dev ? '-.->' : '-->';
      lines.add('  ${ids[edge.from]} $arrow ${ids[edge.to]}');
    }

    final external = nodes.where((n) => n.external).toList();
    if (external.isNotEmpty) {
      lines.add('  classDef external fill:#eeeeee,stroke-dasharray: 3 3;');
      lines.add(
        '  class ${external.map((n) => ids[n.name]).join(',')} external;',
      );
    }

    final inTicket = nodes.where((n) => n.inTicket).toList();
    if (inTicket.isNotEmpty) {
      lines.add('  classDef ticket stroke-width:3px;');
      lines.add(
        '  class ${inTicket.map((n) => ids[n.name]).join(',')} ticket;',
      );
    }

    return lines.join('\n');
  }

  // ...........................................................................
  /// Maps every package name to a unique mermaid safe node id.
  Map<String, String> _mermaidIds(List<GraphNode> nodes) {
    final result = <String, String>{};
    final used = <String>{};

    for (final node in nodes) {
      final base = node.name.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
      var id = base;
      var suffix = 1;
      while (!used.add(id)) {
        id = '${base}_${++suffix}';
      }
      result[node.name] = id;
    }

    return result;
  }

  // ...........................................................................
  /// Maps every organization to a subgraph id that collides with no node id.
  ///
  /// Mermaid keeps subgraph and node ids in one namespace, so an organization
  /// named like one of its packages would otherwise swallow that node.
  Map<String, String> _mermaidOrgIds(
    List<String> orgs,
    Iterable<String> nodeIds,
  ) {
    final result = <String, String>{};
    final used = <String>{...nodeIds};

    for (final org in orgs) {
      final base = 'org_${org.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_')}';
      var id = base;
      var suffix = 1;
      while (!used.add(id)) {
        id = '${base}_${++suffix}';
      }
      result[org] = id;
    }

    return result;
  }

  // ...........................................................................
  /// Renders the graph as JSON.
  ///
  /// An edge carries the same direction the mermaid output draws: `from` is
  /// the package that is depended upon, `to` the one that needs it.
  String _toJson({
    required List<GraphNode> nodes,
    required List<GraphEdge> edges,
    required String orientation,
    required bool transitiveReduction,
  }) {
    final data = <String, dynamic>{
      'orientation': orientation,
      'transitiveReduction': transitiveReduction,
      'nodes': <Map<String, dynamic>>[
        for (final node in nodes)
          <String, dynamic>{
            'name': node.name,
            if (node.path != null) 'path': node.path,
            if (node.language != null) 'language': node.language,
            if (node.organization != null) 'organization': node.organization,
            'external': node.external,
            'inTicket': node.inTicket,
          },
      ],
      'edges': <Map<String, dynamic>>[
        for (final edge in edges)
          <String, dynamic>{'from': edge.from, 'to': edge.to, 'dev': edge.dev},
      ],
    };

    return const JsonEncoder.withIndent('  ').convert(data);
  }
}

/// Mock for [GraphCommand]
class MockGraphCommand extends MockDirCommand<void> implements GraphCommand {}
