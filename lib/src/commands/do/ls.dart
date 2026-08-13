// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

import 'package:gg_multi_workspace/src/commands/do/list/deps.dart';
import 'package:gg_multi_workspace/src/commands/do/list/organizations.dart';
import 'package:gg_multi_workspace/src/commands/do/list/repos.dart';
import 'package:gg_multi_workspace/src/commands/do/list/tickets.dart';

/// Command to list items from the ocean.
/// If no subcommand is provided, it asks the user to choose.
class ListCommand extends Command<dynamic> {
  /// Constructor accepting a log function
  /// and optional workspace path.
  ListCommand({required this.ggLog, String? workspacePath}) {
    // Add subcommands for listing repos, organizations, deps, and tickets.
    addSubcommand(ListReposCommand(ggLog: ggLog, workspacePath: workspacePath));
    addSubcommand(
      ListOrganizationsCommand(ggLog: ggLog, workspacePath: workspacePath),
    );
    addSubcommand(ListDepsCommand(ggLog: ggLog));
    addSubcommand(
      ListTicketsCommand(ggLog: ggLog, workspacePath: workspacePath),
    );
  }

  /// The log function.
  final GgLog ggLog;

  @override
  String get name => 'ls';

  @override
  String get description => 'List repos, organizations or dependencies';
}
