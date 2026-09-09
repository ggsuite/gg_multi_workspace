// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_one/gg_one.dart' show GgPrompts;
import 'package:helix/helix.dart' as helix;
import 'package:path/path.dart' as p;
import 'package:path/path.dart' as path;

import 'package:gg_multi_core/gg_multi_core.dart';

/// Runs one `gg dna` command — `init`, `add` or `build` — with [args].
/// The seam that lets the tests skip the package managers and the network.
typedef RunDna = Future<void> Function(List<String> args);

/// The DNA layer every workspace gets: the gg workflow guides, the skills
/// and the managed `CLAUDE.md` block.
const String workspaceDnaLayer = 'dna_gg';

/// The LICENSE placed in the workspace root. The DNA build insists on one,
/// and a workspace is no package: it says so instead of licensing anything.
const String workspaceLicense = '''
This folder is a gg workspace: a private working directory that holds
checkouts of other repositories. It is not a published package and carries
no license of its own. Every repository below .ocean and in the tickets is
governed by its own LICENSE file.
''';

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
/// Command to initialize the ocean
class InitWorkspaceCommand extends Command<void> {
  /// Constructor. [runDna] replaces the `gg dna` commands in tests.
  InitWorkspaceCommand({
    required this.ggLog,
    String? rootPath,
    RunDna? runDna,
    // coverage:ignore-start
  }) : rootPath = rootPath ?? Directory.current.path,
       _runDna = runDna ?? helixDnaRunner(ggLog);
  // coverage:ignore-end

  /// The log function
  final GgLog ggLog;

  /// Optional root path for where to create the ocean
  final String rootPath;

  final RunDna _runDna;

  String _rel(String absPath) => p.relative(absPath, from: rootPath);

  @override
  String get name => 'workspace';

  @override
  String get description => 'Initialize the ocean';

  @override
  Future<void> run() async {
    final rootDir = Directory(rootPath);

    final wsPath = path.join(rootDir.path, ggMultiOceanFolder);
    final wsDir = Directory(wsPath);

    if (wsDir.existsSync()) {
      ggLog(cWarn('ocean already exists at: ${_rel(wsPath)}'));
      return;
    }

    if (rootDir.listSync().isNotEmpty) {
      ggLog(cError('The directory must be empty to initialize a workspace.'));
      return;
    }

    if (WorkspaceUtils.isInsideExistingWorkspace(rootDir.path)) {
      ggLog(
        cError(
          'Cannot initialize a new workspace inside an existing Gg Multi '
          'workspace.',
        ),
      );
      return;
    }

    // -----------------------------------------------------------------------
    // Create the workspace ---------------------------------------------------
    wsDir.createSync(recursive: true);
    ggLog(cDetail('✓ ocean initialized at: ${_rel(wsPath)}'));

    await _instantiateDna(rootDir.path);
  }

  // ...........................................................................
  /// Places the gg DNA into the workspace root — the folder holding the
  /// ocean. The same three steps as by hand: `gg dna init`, `gg dna add
  /// dna_gg` and `gg dna build`. `add` resolves the latest `dna_gg`, so
  /// a fresh workspace always starts from the current guides and skills.
  ///
  /// A failure does not take the workspace down with it — the ocean is
  /// there and usable — it is reported with the commands to repeat by hand.
  Future<void> _instantiateDna(String root) async {
    final target = root.replaceAll(r'\', '/');
    File(path.join(root, 'LICENSE')).writeAsStringSync(workspaceLicense);
    try {
      await _runDna(['init', '--target', target, '--language', 'dart']);
      await _runDna(['add', workspaceDnaLayer, '--target', target]);
      await _runDna(['build', '--target', target]);
    } catch (e) {
      ggLog(cError('Could not instantiate $workspaceDnaLayer: $e'));
      ggLog(
        cAction(
          'Run manually: gg dna init --language dart, '
          'gg dna add $workspaceDnaLayer, gg dna build',
        ),
      );
      return;
    }
    ggLog(cDetail('✓ $workspaceDnaLayer instantiated in the workspace'));
  }
}
