// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_multi_core/gg_multi_core.dart' show copyDirectory;
import 'package:gg_one/gg_one.dart' show GgPrompts;
import 'package:helix/helix.dart' as helix;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

/// Runs one `gg dna` command — `init`, `add` or `build` — with [args].
/// The seam that lets the tests skip the package managers and the network.
typedef RunDna = Future<void> Function(List<String> args);

/// The DNA layer every workspace and every ticket gets: the gg workflow
/// guides, the skills and the managed `CLAUDE.md` block.
const String workspaceDnaLayer = 'dna_gg';

/// Answers the questions of helix through the prompts of the gg suite —
/// the same menus `gg do publish` draws, and in an embedded gg whatever
/// the embedder assigned to [GgPrompts.current].
Future<int> helixSelectPrompt({
  required String prompt,
  required List<String> options,
}) => GgPrompts.current.select(prompt: prompt, options: options);

/// The `gg dna` runner used outside of tests: helix's own commands, with
/// the prompts of the gg suite — what `gg dna` itself runs.
RunDna helixDnaRunner(GgLog ggLog) {
  final runner = CommandRunner<dynamic>('gg', 'gg')
    ..addCommand(_DnaCommand(ggLog: ggLog));
  return (args) => runner.run(['dna', ...args]);
}

// .............................................................................
/// `gg dna` — helix's subcommands under the name the user knows them by,
/// so a usage error reads `gg dna add …`, not `gg helix add …`.
class _DnaCommand extends Command<dynamic> {
  _DnaCommand({required GgLog ggLog}) {
    helix.Helix(
      ggLog: ggLog,
      selectPrompt: helixSelectPrompt,
    ).subcommands.values.forEach(addSubcommand);
  }

  @override
  String get name => 'dna';

  @override
  String get description => 'Manage the DNA of a repo';
}

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
/// `--quiet` keeps the instantiation to the one line reported when it is
/// through: which file the DNA wrote is detail of a workspace nobody
/// hand-maintains, and the automatic commit helix tries could not work
/// here at all — the folder is no repository.
///
/// A failure is reported with the commands to repeat by hand, never
/// thrown: the workspace is usable without its DNA.
Future<void> instantiateWorkspaceDna({
  required String root,
  required RunDna runDna,
  required GgLog ggLog,
}) async {
  final target = root.replaceAll(r'\', '/');
  try {
    await runDna(['init', '--target', target, '--language', 'dart']);
    await runDna([
      'add',
      workspaceDnaLayer,
      '--target',
      target,
      '--workspace',
      '--quiet',
    ]);
    await runDna(['build', '--target', target, '--workspace', '--quiet']);
  } catch (e) {
    ggLog(cError('Could not instantiate $workspaceDnaLayer: $e'));
    ggLog(
      cAction(
        'Run manually: gg dna init --language dart, '
        'gg dna add $workspaceDnaLayer --workspace, '
        'gg dna build --workspace',
      ),
    );
    return;
  }
  _writeStamp(root);
  _removeScaffold(root);
  ggLog(cDetail('✓ $workspaceDnaLayer instantiated in the workspace'));
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
  final end = content.indexOf(claudeMdEndMarker);
  if (start < 0 || end < start) return null;
  return content.substring(start, end + claudeMdEndMarker.length);
}

/// The managed block of the `CLAUDE.md` in [dir], `null` without one.
String? claudeMdBlockIn(String dir) {
  final file = File(path.join(dir, 'CLAUDE.md'));
  return file.existsSync() ? claudeMdBlock(file.readAsStringSync()) : null;
}

/// Notes the [workspaceDnaLayer] version `add` resolved — read from the
/// lock file before the scaffold goes — so [refreshWorkspaceDna] can tell
/// an up-to-date folder without asking pub again.
void _writeStamp(String root) {
  final lock = File(path.join(root, 'pubspec.lock'));
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
/// it stays in the root — and everything in its `.claude/skills/`, the
/// user's own skills included: which ones the DNA placed is not recorded.
/// A root without DNA leaves the ticket without it.
Future<void> copyWorkspaceDna({
  required String root,
  required String ticketDir,
}) async {
  final block = claudeMdBlockIn(root);
  if (block != null) {
    File(path.join(ticketDir, 'CLAUDE.md')).writeAsStringSync('$block\n');
  }

  final skills = Directory(path.join(root, '.claude', 'skills'));
  if (skills.existsSync()) {
    await copyDirectory(
      skills,
      Directory(path.join(ticketDir, '.claude', 'skills')),
      skipNames: const {},
    );
  }
}

// .............................................................................
/// Removes what `init`/`add` needed only to resolve [workspaceDnaLayer]
/// — the pub manifest, its lock and the resolved package cache.
/// `build --workspace` already left every DNA-owned scaffold file
/// (`dna/`, a manifest) out of its own output; what stays is `.claude/`
/// and `CLAUDE.md`.
void _removeScaffold(String root) {
  for (final name in ['pubspec.yaml', 'pubspec.lock']) {
    final file = File(path.join(root, name));
    if (file.existsSync()) file.deleteSync();
  }
  final dartTool = Directory(path.join(root, '.dart_tool'));
  if (dartTool.existsSync()) dartTool.deleteSync(recursive: true);
}
