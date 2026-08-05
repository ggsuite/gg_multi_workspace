// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

import 'package:gg_multi_workspace/src/commands/do/init/claude.dart';
import 'package:gg_multi_workspace/src/commands/do/init/workspace.dart';

/// Command that groups the things gg can initialize.
class InitCommand extends Command<void> {
  /// Constructor accepting a log function.
  InitCommand({required this.ggLog}) {
    addSubcommand(InitWorkspaceCommand(ggLog: ggLog));
    addSubcommand(DoClaudeCommand(ggLog: ggLog));
  }

  /// Log function
  final GgLog ggLog;

  @override
  String get name => 'init';

  @override
  String get description => 'Initialize workspace or agent files';
}
