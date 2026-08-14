// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

import 'package:gg_multi_workspace/src/commands/do/create/graph.dart';
import 'package:gg_multi_workspace/src/commands/do/create/ticket.dart';

/// Command to create resources such as tickets.
class CreateCommand extends Command<void> {
  /// Constructor accepting a log function.
  CreateCommand({required this.ggLog}) {
    addSubcommand(TicketCommand(ggLog: ggLog));
    addSubcommand(GraphCommand(ggLog: ggLog));
  }

  /// Log function
  final GgLog ggLog;

  @override
  String get name => 'create';

  @override
  String get description => 'Create tickets and other resources';
}
