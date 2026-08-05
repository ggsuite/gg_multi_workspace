// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';

import 'package:gg_multi_workspace/src/backend/list_backend.dart';
import 'package:gg_multi_core/gg_multi_core.dart';

/// Command to list all repositories in the ocean.
class ListReposCommand extends Command<dynamic> {
  /// Constructor with optional workspace path.
  ListReposCommand({
    required this.ggLog,
    String? workspacePath,
    // coverage:ignore-start
  }) : workspacePath =
           workspacePath ?? WorkspaceUtils.defaultOceanWorkspacePath();
  // coverage:ignore-end

  /// The log function.
  final GgLog ggLog;

  /// Optional workspace path override.
  final String workspacePath;

  @override
  String get name => 'repos';

  @override
  String get description => 'List all repos of the ocean';

  @override
  Future<void> run() async {
    final repoInfos = await getAllRepoInfos(workspacePath);
    repoInfos.sort((a, b) => a.name.compareTo(b.name));
    if (repoInfos.isEmpty) {
      ggLog(cDetail('No repositories found in the ocean.'));
    } else {
      for (final repo in repoInfos) {
        ggLog(
          '${repo.name} ${repo.version} '
          '(${repo.language}) from ${repo.organization}',
        );
      }
    }
  }
}
