// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

import 'package:gg_multi_workspace/src/commands/do/import/ticket.dart';

/// Command that groups the things gg can import into the workspace.
class ImportCommand extends Command<dynamic> {
  /// Constructor accepting a log function.
  ImportCommand({required this.ggLog}) {
    addSubcommand(DoCheckoutCommand(ggLog: ggLog));
  }

  /// Log function
  final GgLog ggLog;

  @override
  String get name => 'import';

  @override
  String get description => 'Import something into the workspace';
}
