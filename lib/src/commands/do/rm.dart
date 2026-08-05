// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

import 'package:gg_multi_workspace/src/commands/do/rm/repo.dart';
import 'package:gg_multi_workspace/src/commands/do/rm/ticket.dart';

/// Command group for removing things from the workspace:
/// `rm repo <name…>` deletes repositories from the current ticket (or, with
/// `--from-master`, from the master workspace), `rm ticket` closes the
/// current ticket by moving it to the trash.
class RmCommand extends Command<void> {
  /// Constructor accepting a log function.
  RmCommand({required this.ggLog}) {
    addSubcommand(RemoveRepoCommand(ggLog: ggLog));
    addSubcommand(RemoveTicketCommand(ggLog: ggLog));
  }

  /// Log function
  final GgLog ggLog;

  @override
  String get name => 'rm';

  @override
  String get description => 'Remove repos from a ticket, or a whole ticket';
}
