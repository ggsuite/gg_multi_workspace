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

/// Adds the repository cloned from [url] to the ticket at [ticketPath].
typedef AddToTicket = Future<void> Function({
  required String url,
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

  // ...........................................................................
  @override
  Future<List<String>> knownOrgs() async => _orgSpellings().values.toList();

  // ...........................................................................
  @override
  List<DnaCandidate> dnaCandidates(RepoSpec spec) => [
    for (final repo in _oceanRepos())
      if (p.basename(repo.path).startsWith('dna_') &&
          File(p.join(repo.path, 'dna', '_dna.json')).existsSync())
        ?_dnaCandidate(repo, spec.language),
  ];

  // ...........................................................................
  @override
  Directory? layerDir(String layer) {
    bool matches(Directory repo) => isGitUrl(layer)
        ? _hasRemote(repo, gitReadableUrl(layer))
        : _manifestNames(repo).contains(layer);
    return _oceanRepos().where(matches).firstOrNull;
  }

  // ...........................................................................
  @override
  String? get presetOrg {
    final relative = p.relative(executionPath, from: oceanPath);
    if (relative == '.' || relative.startsWith('..')) return null;
    final org = p.split(relative).first;
    final isRepo = RepoFolderResolver.isRepoDir(
      Directory(p.join(oceanPath, org)),
    );
    return org.startsWith('.') || isRepo ? null : org;
  }

  // ...........................................................................
  @override
  Directory targetDir(RepoSpec spec) =>
      Directory(p.join(oceanPath, _orgFolder(spec.org), spec.name));

  // ...........................................................................
  @override
  Future<List<String>> check(RepoSpec spec, {required bool resumes}) async {
    final target = targetDir(spec);
    return [
      if (ggCommandNames.contains(spec.name))
        '»${spec.name}« is a gg command: »gg do add ${spec.name}« would '
            'not find the repository.',
      for (final repo in _oceanRepos())
        if (!p.equals(repo.path, target.path)) ..._conflicts(repo, spec),
      if (_ticketFolderTaken(spec, resumes: resumes))
        'The ticket already has a folder »${spec.name}«.',
    ];
  }

  // ...........................................................................
  @override
  String? afterCreateDescription(RepoSpec spec) => _addsToTicket
      ? 'add it to the ticket ${p.basename(_ticketPath!)}'
      : 'keep it in the ocean';

  // ...........................................................................
  @override
  Future<void> afterCreate({
    required RepoSpec spec,
    required Directory directory,
    required GgLog ggLog,
  }) async {
    _registerOrg(spec);
    if (!_addsToTicket) return;
    await _add(
      url: spec.cloneUrl,
      ticketPath: _ticketPath!,
      oceanPath: oceanPath,
      ggLog: ggLog,
    );
  }

  // ...........................................................................
  /// Adds [url] the way `gg do add <url>` does; a repo already in the
  /// ticket is not copied again. `--no-fetch`: dirty or feature-branch
  /// dependencies in the ocean must not fail the run after the push.
  static Future<void> addWithAddCommand({
    required String url,
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
    await runner.run(['add', '--no-fetch', url]);
  }

  /// The folder gg was started in.
  final String executionPath;

  /// The `.ocean` folder of the workspace.
  final String oceanPath;

  /// Whether a repository created inside a ticket is added to it.
  final bool addToTicket;

  /// gg's top-level commands; gg tests it, as gg depends on this package.
  static const ggCommandNames = {
    'can', 'did', 'do', 'one', 'multi', 'dna', 'run', 'help', 'gg', //
  };

  // ...........................................................................
  /// A host in a workspace below [root]; tests pass what they care about.
  factory WorkspaceRepoHost.example({
    Directory? root,
    String? executionPath,
    bool? addToTicket,
    AddToTicket? add,
  }) {
    final rootPath = (root ?? Directory.systemTemp).path;
    return WorkspaceRepoHost(
      executionPath: executionPath ?? rootPath,
      oceanPath: p.join(rootPath, ggMultiOceanFolder),
      addToTicket: addToTicket ?? true,
      add: add,
    );
  }

  // ######################
  // Private
  // ######################

  final AddToTicket _add;

  // ...........................................................................
  String? get _ticketPath => WorkspaceUtils.detectTicketPath(executionPath);

  // ...........................................................................
  bool get _addsToTicket => addToTicket && _ticketPath != null;

  // ...........................................................................
  /// The repositories of the ocean, in org folders or still flat.
  Iterable<Directory> _oceanRepos() => RepoFolderResolver.repoDirs(oceanPath)
      .where(
        (d) =>
            !p.basename(d.path).startsWith('.') &&
            RepoFolderResolver.isRepoDir(d),
      );

  // ...........................................................................
  /// The known orgs by their lower-cased name; an org folder's spelling wins.
  Map<String, String> _orgSpellings() => {
    for (final org in OrganizationUtils.readOrganizations(oceanPath))
      org.name.toLowerCase(): org.name,
    for (final repo in _oceanRepos())
      if (!p.equals(repo.parent.path, oceanPath))
        p.basename(repo.parent.path).toLowerCase(): p.basename(
          repo.parent.path,
        ),
  };

  // ...........................................................................
  /// The ocean folder of [org]: an existing one in any case, else [org] as
  /// typed — the folder `gg do add` takes from the URL.
  String _orgFolder(String org) => _orgSpellings()[org.toLowerCase()] ?? org;

  // ...........................................................................
  /// What speaks against [spec] because of the ocean repository [repo].
  List<String> _conflicts(Directory repo, RepoSpec spec) => [
    if (_manifestNames(repo).contains(spec.packageName))
      'The ocean already has a package »${spec.packageName}« in '
          '${repo.path}.',
    if (p.basename(repo.path).toLowerCase() == spec.name.toLowerCase())
      '»${spec.name}« exists in ${_location(repo)} too: '
          '»gg do add ${spec.name}« would be ambiguous.',
  ];

  // ...........................................................................
  String _location(Directory repo) => p.equals(repo.parent.path, oceanPath)
      ? 'the ocean'
      : 'org ${p.basename(repo.parent.path)}';

  // ...........................................................................
  /// Whether the ticket folder of [spec] holds something other than the
  /// repository an earlier run of the same command created.
  bool _ticketFolderTaken(RepoSpec spec, {required bool resumes}) {
    if (!_addsToTicket) return false;
    final folder = Directory(p.join(_ticketPath!, spec.name));
    if (!folder.existsSync()) return false;
    return !resumes || !_hasRemote(folder, spec.webUrl);
  }

  // ...........................................................................
  /// Whether the git remote of [repo] is the repository [url] names.
  bool _hasRemote(Directory repo, String url) {
    final remote = RepoFolderResolver.remoteUrl(repo);
    final wanted = RepoFolderResolver.urlIdentity(url);
    return remote != null &&
        wanted != null &&
        RepoFolderResolver.urlIdentity(remote) == wanted;
  }

  // ...........................................................................
  /// Records the org of [spec] in `.organizations` unless it is known, in
  /// the spelling of its ocean folder.
  void _registerOrg(RepoSpec spec) {
    final org = spec.org.toLowerCase();
    final known = OrganizationUtils.readOrganizations(oceanPath)
        .any((o) => o.name.toLowerCase() == org);
    if (known) return;
    OrganizationUtils.appendOrganization(
      oceanPath,
      'https://github.com/${_orgFolder(spec.org)}/${spec.name}.git',
    );
  }

  // ...........................................................................
  /// The layer by its registry name, or by its git remote when unpublished.
  DnaCandidate? _dnaCandidate(Directory repo, RepoLanguage language) {
    final isDart = language == RepoLanguage.dart;
    final file = File(
      p.join(repo.path, isDart ? 'pubspec.yaml' : 'package.json'),
    );
    final manifest = _read(file);
    final name = manifest?['name'];
    if (name is! String) return null;
    final unpublished = isDart
        ? manifest!['publish_to'] == 'none'
        : manifest!['private'] == true;
    final remote = unpublished ? RepoFolderResolver.remoteUrl(repo) : null;
    return DnaCandidate(label: name, ref: remote ?? name);
  }

  // ...........................................................................
  /// The package names of [repo]; a bridge has a Dart and an npm one.
  Set<String> _manifestNames(Directory repo) => {
    for (final name in ['pubspec.yaml', 'package.json'])
      if (_read(File(p.join(repo.path, name)))?['name'] case final String n) n,
  };

  // ...........................................................................
  /// The manifest [file] as a map, or null when it is missing or no map.
  Map<dynamic, dynamic>? _read(File file) {
    if (!file.existsSync()) return null;
    try {
      final content = file.readAsStringSync();
      final Object? data = file.path.endsWith('.json')
          ? jsonDecode(content)
          : loadYaml(content);
      return data is Map ? data : null;
    } on Object {
      return null;
    }
  }
}
