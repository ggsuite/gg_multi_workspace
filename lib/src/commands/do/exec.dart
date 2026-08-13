// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

import 'package:gg_multi_workspace/src/commands/do/exec/cmd.dart';

/// Command that groups the things gg can execute across the ticket repos.
class ExecCommand extends Command<void> {
  /// Constructor accepting a log function.
  ExecCommand({required this.ggLog}) {
    addSubcommand(DoExecuteCommand(ggLog: ggLog));
  }

  /// Log function
  final GgLog ggLog;

  @override
  String get name => 'exec';

  @override
  String get description => 'Execute something in all ticket repos';
}
