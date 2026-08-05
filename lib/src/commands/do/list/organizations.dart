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

/// Command to list all organizations from repos in the ocean.
class ListOrganizationsCommand extends Command<dynamic> {
  /// Constructor with optional workspace path.
  ListOrganizationsCommand({
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
  String get name => 'orgs';

  @override
  String get description => 'List all organizations of the ocean';

  @override
  Future<void> run() async {
    final repoInfos = await getAllRepoInfos(workspacePath);
    final orgSet = <String>{};
    for (final repo in repoInfos) {
      orgSet.add(repo.organization);
    }
    final orgs = orgSet.toList()..sort();
    if (orgs.isEmpty) {
      ggLog(cDetail('No organizations found.'));
    } else {
      for (final org in orgs) {
        if (org != 'unknown') {
          ggLog('$org -- https://github.com/orgs/$org/');
        } else {
          ggLog(org);
        }
      }
    }
  }
}
