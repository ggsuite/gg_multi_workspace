// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as p;
import 'package:path/path.dart' as path;

import 'package:gg_multi_core/gg_multi_core.dart';
import 'package:gg_multi_workspace/src/backend/workspace_dna.dart';

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

  /// An existing ocean makes the command a repetition, not an error: the
  /// folder stays as it is and only the DNA is instantiated again. That is
  /// what brings a workspace created before the DNA existed - or one whose
  /// `CLAUDE.md` was lost - up to the current guides and skills.
  ///
  /// The two guards below only apply to a workspace that is about to be
  /// created. A root that already holds the ocean is never empty, and
  /// [WorkspaceUtils.isInsideExistingWorkspace] starts at the directory
  /// itself, so both would refuse the repetition.
  @override
  Future<void> run() async {
    final rootDir = Directory(rootPath);

    final wsPath = path.join(rootDir.path, ggMultiOceanFolder);
    final wsDir = Directory(wsPath);

    if (wsDir.existsSync()) {
      ggLog(cWarn('ocean already exists at: ${_rel(wsPath)}'));
    } else {
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

      // ---------------------------------------------------------------------
      // Create the workspace -------------------------------------------------
      wsDir.createSync(recursive: true);
      ggLog(cDetail('✓ ocean initialized at: ${_rel(wsPath)}'));
    }

    await instantiateWorkspaceDna(
      root: rootDir.path,
      runDna: _runDna,
      ggLog: ggLog,
      place: 'workspace',
    );
  }
}
