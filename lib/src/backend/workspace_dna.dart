// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_create_repo/gg_create_repo.dart' show RunDna;
import 'package:gg_log/gg_log.dart';
import 'package:gg_multi_core/gg_multi_core.dart' show copyDirectory;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

/// The DNA layer every workspace and every ticket gets: the gg workflow
/// guides, the skills and the managed `CLAUDE.md` block.
const String workspaceDnaLayer = 'dna_gg';

// .............................................................................
/// Places [workspaceDnaLayer] into the workspace [root] — the folder
/// holding the ocean. The same three steps as by hand: `gg dna init`,
/// `gg dna add dna_gg --workspace` and `gg dna build --workspace`. `add`
/// resolves the latest `dna_gg`, so every call starts from the current
/// guides and skills. `--workspace` instantiates only `.claude/` and the
/// managed `CLAUDE.md` block — a workspace is no package of its own, so
/// it never gets `doc/`, `scripts/`, `.github/` or a DNA manifest. `add`
/// builds right after installing the layer (the same instantiation
/// `build` performs), so it needs the flag as much as the explicit
/// `build` call that follows it.
///
/// The three steps run in an empty temporary folder, never in [root]:
/// `init` and `add` need a pub manifest, a lock, `.dart_tool/` and a
/// `dna/` scaffold to resolve the layer, and a step that fails half way
/// would leave them in the workspace. Only when all three steps are
/// through is the result taken over (see [_takeOver]): its `.claude/` is
/// copied into [root] — over the files of the same name, beside the
/// user's own — and its managed `CLAUDE.md` block replaces the one in the
/// root's `CLAUDE.md`, or is appended to it; the user's own text stays.
/// The temporary folder is removed either way. It starts empty on
/// purpose: helix refuses to overwrite an existing file outside a git
/// repository, and neither the folder nor a workspace root is one. A
/// temporary folder that happens to lie inside a git work tree gets a
/// repository of its own first, so the commit helix tries after a build
/// never lands in that unrelated repository.
///
/// A successful run also removes what an earlier run of the in-root
/// instantiation left behind when it failed half way — see
/// [_removeOldScaffold].
///
/// `--quiet` keeps the instantiation to the one line reported when it is
/// through: which file the DNA wrote is detail of a workspace nobody
/// hand-maintains. For `init` it also drops the next steps it suggests by
/// hand, `git init` and `gg dna add`: this function adds the layer
/// itself.
///
/// A failure is reported with what to do about it, never thrown: the
/// workspace is usable without its DNA. [createTemp] replaces the system
/// temporary folder in tests.
Future<void> instantiateWorkspaceDna({
  required String root,
  required RunDna runDna,
  required GgLog ggLog,
  Directory Function()? createTemp,
}) async {
  Directory? build;
  try {
    build = (createTemp ?? _systemTemp)();
    await _isolateFromEnclosingRepo(build.path);
    final target = build.path.replaceAll(r'\', '/');
    await runDna(['init', '--target', target, '--language', 'dart', '--quiet']);
    await runDna([
      'add',
      workspaceDnaLayer,
      '--target',
      target,
      '--workspace',
      '--quiet',
    ]);
    await runDna(['build', '--target', target, '--workspace', '--quiet']);
    await _takeOver(build: build.path, root: root);
  } catch (e) {
    ggLog(cError('Could not instantiate $workspaceDnaLayer: $e'));
    ggLog(cAction(_failureHint(e)));
    return;
  } finally {
    if (build != null) _remove(build);
  }
  try {
    _removeOldScaffold(root);
    // coverage:ignore-start
  } on FileSystemException catch (e) {
    ggLog(cWarn('Could not remove the old DNA scaffold from the root: $e'));
  }
  // coverage:ignore-end
  ggLog(cDetail('✓ $workspaceDnaLayer instantiated in the workspace'));
}

Directory _systemTemp() =>
    Directory.systemTemp.createTempSync('gg_workspace_dna_');

/// Gives [dir] a git repository of its own when it lies inside a git
/// work tree — the folder git would otherwise report and commit to.
Future<void> _isolateFromEnclosingRepo(String dir) async {
  var current = Directory(dir).absolute;
  while (true) {
    final dotGit = path.join(current.path, '.git');
    if (FileSystemEntity.typeSync(dotGit) != FileSystemEntityType.notFound) {
      break;
    }
    final parent = current.parent;
    if (parent.path == current.path) return;
    current = parent;
  }
  final result = await Process.run('git', [
    'init',
    '-q',
  ], workingDirectory: dir);
  if (result.exitCode != 0) {
    throw Exception('git init failed in $dir: ${result.stderr}'.trim());
  }
}

/// What helix reports when a layer's `dna/_dna.json` carries a format
/// version newer than the helix gg was installed with.
final RegExp _unsupportedFormatVersion = RegExp(
  r'format version \d+ is not supported',
);

/// What to do after [instantiateWorkspaceDna] failed with [error]. A
/// layer in a format the helix inside gg cannot read needs a newer gg —
/// `dart pub global activate gg` resolves gg's dependencies anew and
/// brings the newest helix gg allows. A broken managed block in the
/// root's `CLAUDE.md` fails every run until it is repaired. Anything else
/// is repeated by the command that instantiates the DNA of an existing
/// workspace again.
String _failureHint(Object error) {
  if (_unsupportedFormatVersion.hasMatch('$error')) {
    return 'The helix inside gg is too old for the latest '
        '$workspaceDnaLayer. Update gg: dart pub global activate gg';
  }
  if (error is StateError) {
    return 'Add the missing "$claudeMdEndMarker" to CLAUDE.md in the '
        'workspace root, then run gg do init workspace there.';
  }
  return 'Run gg do init workspace in the workspace root to try again.';
}

/// Copies what the DNA build in [build] produced for the workspace into
/// [root]: `.claude/` and the managed `CLAUDE.md` block, then the stamp
/// of the version it resolved. The new `CLAUDE.md` is worked out before
/// anything is written, so a root `CLAUDE.md` whose block cannot be
/// replaced leaves the root as it was. The stamp goes first and comes
/// back last: a copy that fails half way leaves a root without stamp,
/// which the next ticket instantiates again.
///
/// `copyDirectory` renames a `*.darta` file to `*.dart` — no `dna_gg`
/// file is named that way.
Future<void> _takeOver({required String build, required String root}) async {
  final block = claudeMdBlockIn(build);
  final claudeMd = File(path.join(root, 'CLAUDE.md'));
  final newClaudeMd = block == null
      ? null
      : upsertClaudeMdBlock(
          claudeMd.existsSync() ? claudeMd.readAsStringSync() : '',
          block,
        );

  final stamp = File(path.join(root, dnaVersionStampPath));
  if (stamp.existsSync()) stamp.deleteSync();

  // A layer the new build no longer ships takes its file along.
  final built = claudeLayerFilesIn(build).map(path.basename).toSet();
  for (final stale in claudeLayerFilesIn(root)) {
    if (!built.contains(path.basename(stale))) File(stale).deleteSync();
  }

  final claude = Directory(path.join(build, '.claude'));
  if (claude.existsSync()) {
    await _copyClaudeFolder(claude, Directory(path.join(root, '.claude')));
  }
  if (newClaudeMd != null) claudeMd.writeAsStringSync(newClaudeMd);
  _writeStamp(build: build, root: root);
}

/// The Claude Code settings file below `.claude/`.
const String claudeSettingsFile = 'settings.json';

/// The `.claude/CLAUDE_<layer>.md` files in [dir], sorted — one per DNA
/// layer that ships a `CLAUDE.md`, imported by the managed block.
List<String> claudeLayerFilesIn(String dir) {
  final claude = Directory(path.join(dir, '.claude'));
  if (!claude.existsSync()) return const [];
  return claude
      .listSync(followLinks: false)
      .whereType<File>()
      .map((f) => f.path)
      .where((p) {
        final name = path.basename(p);
        return name.startsWith('CLAUDE_') && name.endsWith('.md');
      })
      .toList()
    ..sort();
}

/// The folder below `.claude/` holding the scripts the hooks run.
const String claudeHooksFolder = 'hooks';

/// Copies everything in the `.claude/` folder [source] over [destination]
/// — beside the user's own files, over those of the same name — except
/// `settings.json`, which is merged by [mergeClaudeSettings]: the user's
/// own settings and hooks in it stay.
Future<void> _copyClaudeFolder(Directory source, Directory destination) async {
  destination.createSync(recursive: true);
  for (final entity in source.listSync(followLinks: false)) {
    final name = path.basename(entity.path);
    final target = path.join(destination.path, name);
    if (entity is Directory) {
      await copyDirectory(entity, Directory(target), skipNames: const {});
    } else if (name == claudeSettingsFile && entity is File) {
      _mergeSettingsInto(entity, File(target), source);
    } else if (entity is Link) {
      final link = Link(target);
      if (link.existsSync()) link.deleteSync();
      link.createSync(entity.targetSync());
    } else if (entity is File) {
      entity.copySync(target);
    }
  }
}

/// Writes the DNA settings [dna] into [target], merged with what [target]
/// holds. The hook scripts the DNA ships are the files in the `hooks`
/// folder beside [dna] in [dnaClaude].
void _mergeSettingsInto(File dna, File target, Directory dnaClaude) {
  final hooks = Directory(path.join(dnaClaude.path, claudeHooksFolder));
  final scripts = hooks.existsSync()
      ? hooks.listSync().whereType<File>().map((f) => path.basename(f.path))
      : const <String>[];
  target.writeAsStringSync(
    mergeClaudeSettings(
      existing: target.existsSync() ? target.readAsStringSync() : null,
      dna: dna.readAsStringSync(),
      dnaHookScripts: scripts.toSet(),
    ),
  );
}

/// The Claude Code settings [existing] with the DNA settings [dna] merged
/// in. The keys of [existing] win, except for `hooks`: per event, the hook
/// groups of [existing] that run one of the [dnaHookScripts] — what an
/// earlier DNA placed — are replaced by the groups of [dna]; the user's
/// own groups stay. Without [existing], it is [dna]. An [existing] that is
/// no JSON object is left as it is.
String mergeClaudeSettings({
  required String? existing,
  required String dna,
  required Set<String> dnaHookScripts,
}) {
  final dnaJson = jsonDecode(dna);
  if (existing == null || dnaJson is! Map<String, dynamic>) return dna;
  final Object? own;
  try {
    own = jsonDecode(existing);
  } on FormatException {
    return existing;
  }
  if (own is! Map<String, dynamic>) return existing;

  final merged = <String, dynamic>{...own};
  for (final entry in dnaJson.entries) {
    if (entry.key != 'hooks') merged.putIfAbsent(entry.key, () => entry.value);
  }

  bool runsDnaScript(Object? group) {
    final hooks = group is Map ? group['hooks'] : null;
    if (hooks is! List) return false;
    return hooks.any((hook) {
      final command = hook is Map ? hook['command'] : null;
      return command is String &&
          dnaHookScripts.any(
            (s) => command.contains('.claude/$claudeHooksFolder/$s'),
          );
    });
  }

  final ownHooks = own['hooks'];
  final dnaHooks = dnaJson['hooks'];
  final hooks = <String, dynamic>{
    if (ownHooks is Map<String, dynamic>)
      for (final entry in ownHooks.entries)
        entry.key: entry.value is List
            ? [...(entry.value as List).where((g) => !runsDnaScript(g))]
            : entry.value,
  };
  if (dnaHooks is Map<String, dynamic>) {
    for (final entry in dnaHooks.entries) {
      final groups = hooks[entry.key];
      hooks[entry.key] = [
        if (groups is List) ...groups,
        if (entry.value is List) ...entry.value as List,
      ];
    }
  }
  hooks.removeWhere((_, groups) => groups is List && groups.isEmpty);
  if (hooks.isEmpty) {
    merged.remove('hooks');
  } else {
    merged['hooks'] = hooks;
  }
  return '${const JsonEncoder.withIndent('  ').convert(merged)}\n';
}

/// [content] of a `CLAUDE.md` with its managed block replaced by [block]
/// — or [block] appended after a blank line when it has none yet, the
/// way helix places it. Throws a [StateError] when a start marker has no
/// end marker after it: appending would leave the file with two blocks.
String upsertClaudeMdBlock(String content, String block) {
  final old = claudeMdBlock(content);
  if (old != null) return content.replaceFirst(old, block);
  if (content.contains(claudeMdStartMarker)) {
    throw StateError(
      'CLAUDE.md holds "$claudeMdStartMarker" without a matching '
      '"$claudeMdEndMarker".',
    );
  }
  final own = content.trimRight();
  return own.isEmpty ? '$block\n' : '$own\n\n$block\n';
}

/// Removes the temporary [dir] of [instantiateWorkspaceDna]. A folder
/// that cannot be removed — a file another process still holds — stays
/// for the system to clean up: it is no reason to fail the run.
void _remove(Directory dir) {
  try {
    dir.deleteSync(recursive: true);
    // coverage:ignore-start
  } on FileSystemException catch (_) {}
  // coverage:ignore-end
}

/// Removes from [root] what the in-root instantiation of gg versions
/// before the temporary folder left there when a step failed: the pub
/// scaffold — `pubspec.yaml`, `pubspec.lock`, `.dart_tool/` — and the
/// `dna/` folder. Only a `pubspec.yaml` that is recognizably that
/// scaffold counts — the skeleton `helix init` writes (`description: A
/// Dart project.`, `publish_to: none`) with [workspaceDnaLayer] as a dev
/// dependency — and `dna/` only beside it and only while it holds
/// nothing but the config files `init` and `add` write. Anything else in
/// the root belongs to the user and stays.
void _removeOldScaffold(String root) {
  final pubspec = File(path.join(root, 'pubspec.yaml'));
  if (!pubspec.existsSync() || !_isDnaScaffold(pubspec)) return;
  pubspec.deleteSync();
  final lock = File(path.join(root, 'pubspec.lock'));
  if (lock.existsSync()) lock.deleteSync();
  final dartTool = Directory(path.join(root, '.dart_tool'));
  if (dartTool.existsSync()) dartTool.deleteSync(recursive: true);
  final dna = Directory(path.join(root, 'dna'));
  if (!dna.existsSync()) return;
  final names = dna
      .listSync(recursive: true)
      .map((e) => path.relative(e.path, from: dna.path))
      .toSet();
  if (names.difference(const {'_dna.json', '_vars.json'}).isEmpty) {
    dna.deleteSync(recursive: true);
  }
}

/// Whether [pubspec] is the scaffold `helix init` and `add` write for
/// [workspaceDnaLayer] — see [_removeOldScaffold].
bool _isDnaScaffold(File pubspec) {
  try {
    final yaml = loadYaml(pubspec.readAsStringSync());
    if (yaml is! YamlMap) return false;
    final devDependencies = yaml['dev_dependencies'];
    return yaml['description'] == 'A Dart project.' &&
        yaml['publish_to'] == 'none' &&
        devDependencies is YamlMap &&
        devDependencies.containsKey(workspaceDnaLayer);
  } on Exception {
    return false;
  }
}

// .............................................................................
/// Where [instantiateWorkspaceDna] notes the [workspaceDnaLayer] version
/// it placed, relative to the folder it placed it in.
const String dnaVersionStampPath = '.claude/.dna_gg_version';

/// Marker that opens the managed `CLAUDE.md` block helix writes.
const String claudeMdStartMarker = '<!-- helix:claude_md:start -->';

/// Marker that closes the managed `CLAUDE.md` block helix writes.
const String claudeMdEndMarker = '<!-- helix:claude_md:end -->';

/// The managed block of a `CLAUDE.md` [content], markers included —
/// `null` when it holds no complete one.
String? claudeMdBlock(String content) {
  final start = content.indexOf(claudeMdStartMarker);
  if (start < 0) return null;
  // Searched from the start marker on: an end marker standing alone
  // before the block must not hide it.
  final end = content.indexOf(claudeMdEndMarker, start);
  if (end < 0) return null;
  return content.substring(start, end + claudeMdEndMarker.length);
}

/// The managed block of the `CLAUDE.md` in [dir], `null` without one.
String? claudeMdBlockIn(String dir) {
  final file = File(path.join(dir, 'CLAUDE.md'));
  return file.existsSync() ? claudeMdBlock(file.readAsStringSync()) : null;
}

/// Notes in [root] the [workspaceDnaLayer] version `add` resolved — read
/// from the lock file of the [build] folder — so [refreshWorkspaceDna]
/// can tell an up-to-date folder without asking pub again.
void _writeStamp({required String build, required String root}) {
  final lock = File(path.join(build, 'pubspec.lock'));
  if (!lock.existsSync()) return;
  final yaml = loadYaml(lock.readAsStringSync());
  final packages = yaml is YamlMap ? yaml['packages'] : null;
  final package = packages is YamlMap ? packages[workspaceDnaLayer] : null;
  final version = package is YamlMap ? package['version'] : null;
  if (version is! String) return;
  File(path.join(root, dnaVersionStampPath))
    ..createSync(recursive: true)
    ..writeAsStringSync(version);
}

// .............................................................................
/// Asks pub.dev for the latest published version of [workspaceDnaLayer].
/// `null` when pub.dev cannot be reached or answers with anything else —
/// the caller then instantiates instead of guessing.
Future<String?> latestWorkspaceDnaVersion({
  Future<http.Response> Function(Uri)? fetcher,
}) async {
  final fetch = fetcher ?? http.get;
  try {
    final response = await fetch(
      Uri.parse('https://pub.dev/api/packages/$workspaceDnaLayer'),
    ).timeout(const Duration(seconds: 2));
    if (response.statusCode != 200) return null;
    final json = jsonDecode(response.body);
    final latest = json is Map ? json['latest'] : null;
    final version = latest is Map ? latest['version'] : null;
    return version is String ? version : null;
  } catch (_) {
    return null;
  }
}

// .............................................................................
/// Brings the gg DNA of the workspace [root] to the latest
/// [workspaceDnaLayer]. The cheap path first: one look at pub.dev
/// ([latestVersion]), and a root that holds its managed `CLAUDE.md` block
/// is left as it is when its stamp names that version — or when pub.dev
/// cannot be asked: helix needs pub.dev as well, so offline the DNA that
/// is there is the best there is. Only a new release or a root without
/// its DNA pays for the instantiation.
Future<void> refreshWorkspaceDna({
  required String root,
  required RunDna runDna,
  required GgLog ggLog,
  required Future<String?> Function() latestVersion,
}) async {
  final latest = await latestVersion();
  final stamp = File(path.join(root, dnaVersionStampPath));
  final upToDate =
      claudeMdBlockIn(root) != null &&
      stamp.existsSync() &&
      (latest == null || stamp.readAsStringSync().trim() == latest);
  if (upToDate) return;

  await instantiateWorkspaceDna(root: root, runDna: runDna, ggLog: ggLog);
}

// .............................................................................
/// Copies the gg DNA of the workspace [root] into [ticketDir]: the managed
/// block of its `CLAUDE.md` — only the block, the user's own text around
/// it stays in the root — together with the `.claude/CLAUDE_<layer>.md`
/// files it imports, and everything in its `.claude/skills/`, the
/// user's own skills included: which ones the DNA placed is not recorded.
/// The same holds for the scripts in `.claude/hooks/` and the
/// `.claude/settings.json` that runs them: Claude Code reads the settings
/// of the folder it starts in only, so a session in the ticket needs its
/// own. A root without DNA leaves the ticket without it.
Future<void> copyWorkspaceDna({
  required String root,
  required String ticketDir,
}) async {
  final block = claudeMdBlockIn(root);
  if (block != null) {
    File(path.join(ticketDir, 'CLAUDE.md')).writeAsStringSync('$block\n');
    for (final layerFile in claudeLayerFilesIn(root)) {
      final target = File(
        path.join(ticketDir, '.claude', path.basename(layerFile)),
      );
      target.parent.createSync(recursive: true);
      File(layerFile).copySync(target.path);
    }
  }

  for (final folder in const ['skills', claudeHooksFolder]) {
    final source = Directory(path.join(root, '.claude', folder));
    if (source.existsSync()) {
      await copyDirectory(
        source,
        Directory(path.join(ticketDir, '.claude', folder)),
        skipNames: const {},
      );
    }
  }

  final settings = File(path.join(root, '.claude', claudeSettingsFile));
  if (settings.existsSync()) {
    _mergeSettingsInto(
      settings,
      File(path.join(ticketDir, '.claude', claudeSettingsFile)),
      Directory(path.join(root, '.claude')),
    );
  }
}
