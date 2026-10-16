// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_create_repo/gg_create_repo.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_multi_core/gg_multi_core.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../commands/do/add.dart';

/// Adds the repository [name] to the ticket at [ticketPath].
typedef AddToTicket = Future<void> Function({
  required String name,
  required String ticketPath,
  required String oceanPath,
  required GgLog ggLog,
});

/// Places a new repository into the ocean and, inside a ticket, adds it.
class WorkspaceRepoHost extends RepoHost {
  /// Constructor
  WorkspaceRepoHost({
    required this.executionPath,
    required this.oceanPath,
    this.addToTicket = true,
    AddToTicket? add,
  }) : _add = add ?? addWithAddCommand;

  /// A host in a workspace below [root]; tests pass what they care about.
  factory WorkspaceRepoHost.example({
    required Directory root,
    String? executionPath,
    bool? addToTicket,
    AddToTicket? add,
  }) => WorkspaceRepoHost(
    executionPath: executionPath ?? root.path,
    oceanPath: p.join(root.path, ggMultiOceanFolder),
    addToTicket: addToTicket ?? true,
    add: add,
  );

  // ...........................................................................
  @override
  Future<List<String>> knownOrgs() async => {
    ...OrganizationUtils.readOrganizations(oceanPath).map((o) => o.name),
    ..._orgDirs().map((d) => p.basename(d.path)),
  }.toList();

  @override
  List<DnaCandidate> dnaCandidates(RepoSpec spec) => [
    for (final repo in _oceanRepos())
      if (p.basename(repo.path).startsWith('dna_') &&
          File(p.join(repo.path, 'dna', '_dna.json')).existsSync())
        ?_dnaCandidate(repo, spec.language),
  ];

  @override
  String? get presetOrg {
    final relative = p.relative(executionPath, from: oceanPath);
    if (relative == '.' || relative.startsWith('..')) return null;
    return p.split(relative).first;
  }

  @override
  Directory targetDir(RepoSpec spec) =>
      Directory(p.join(oceanPath, spec.org, spec.name));

  @override
  Future<List<String>> check(RepoSpec spec) async => [
    if (_ggCommands.contains(spec.name))
      '»${spec.name}« is a gg command: »gg do add ${spec.name}« would '
          'not find the repository.',
    for (final repo in _oceanRepos())
      if (_manifestNames(repo).contains(spec.packageName) &&
          !p.equals(repo.path, targetDir(spec).path))
        'The ocean already has a package »${spec.packageName}« in '
            '${repo.path}.',
    if (_ticketPath != null &&
        Directory(p.join(_ticketPath!, spec.name)).existsSync())
      'The ticket already has a folder »${spec.name}«.',
  ];

  @override
  String? afterCreateDescription(RepoSpec spec) => _addsToTicket
      ? 'add it to the ticket ${p.basename(_ticketPath!)}'
      : 'keep it in the ocean';

  @override
  Future<void> afterCreate({
    required RepoSpec spec,
    required Directory directory,
    required GgLog ggLog,
  }) async {
    OrganizationUtils.appendOrganization(oceanPath, '${spec.webUrl}.git');
    if (!_addsToTicket) return;
    await _add(
      name: spec.name,
      ticketPath: _ticketPath!,
      oceanPath: oceanPath,
      ggLog: ggLog,
    );
  }

  /// The folder gg was started in.
  final String executionPath;

  /// The `.ocean` folder of the workspace.
  final String oceanPath;

  /// Whether a repository created inside a ticket is added to it.
  final bool addToTicket;

  // ...........................................................................
  /// Adds [name] the way `gg do add <name>` does.
  // coverage:ignore-start
  static Future<void> addWithAddCommand({
    required String name,
    required String ticketPath,
    required String oceanPath,
    required GgLog ggLog,
  }) async {
    final runner = CommandRunner<void>('gg', 'gg')
      ..addCommand(
        AddCommand(
          ggLog: ggLog,
          executionPath: ticketPath,
          oceanWorkspacePath: oceanPath,
        ),
      );
    await runner.run(['add', name]);
  }
  // coverage:ignore-end

  // ######################
  // Private
  // ######################

  final AddToTicket _add;

  static const _ggCommands = {
    'can', 'did', 'do', 'one', 'multi', 'dna', 'run', 'help', 'gg', //
  };

  String? get _ticketPath => WorkspaceUtils.detectTicketPath(executionPath);

  bool get _addsToTicket => addToTicket && _ticketPath != null;

  // ...........................................................................
  Iterable<Directory> _orgDirs() {
    final ocean = Directory(oceanPath);
    if (!ocean.existsSync()) return const [];
    return ocean.listSync().whereType<Directory>().where(
      (d) => !p.basename(d.path).startsWith('.'),
    );
  }

  // ...........................................................................
  Iterable<Directory> _oceanRepos() => _orgDirs().expand(
    (org) => org.listSync().whereType<Directory>().where(
      (d) => !p.basename(d.path).startsWith('.'),
    ),
  );

  // ...........................................................................
  /// The layer by its registry name, for the language of the new repo.
  DnaCandidate? _dnaCandidate(Directory repo, RepoLanguage language) {
    final file = language == RepoLanguage.dart
        ? File(p.join(repo.path, 'pubspec.yaml'))
        : File(p.join(repo.path, 'package.json'));
    if (!file.existsSync()) return null;
    final name = _nameIn(file);
    return name == null ? null : DnaCandidate(label: name, ref: name);
  }

  // ...........................................................................
  /// The package names of [repo]; a bridge has a Dart and an npm one.
  Set<String> _manifestNames(Directory repo) => {
    for (final name in ['pubspec.yaml', 'package.json'])
      if (File(p.join(repo.path, name)).existsSync())
        ?_nameIn(File(p.join(repo.path, name))),
  };

  // ...........................................................................
  String? _nameIn(File file) {
    try {
      final content = file.readAsStringSync();
      final Object? data = file.path.endsWith('.json')
          ? jsonDecode(content)
          : loadYaml(content);
      return data is Map ? data['name'] as String? : null;
    } on Object {
      return null;
    }
  }
}
