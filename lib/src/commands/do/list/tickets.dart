// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;

import 'package:gg_multi_core/gg_multi_core.dart';

/// Command to list all tickets and their descriptions.
class ListTicketsCommand extends Command<void> {
  /// Constructor with optional workspace path
  ListTicketsCommand({
    required this.ggLog,
    String? workspacePath,
    // coverage:ignore-start
  }) : workspacePath =
           workspacePath ?? WorkspaceUtils.defaultGgMultiWorkspacePath();
  // coverage:ignore-end

  /// The logger function
  final GgLog ggLog;

  /// The resolved ocean path
  final String workspacePath;

  @override
  String get name => 'tickets';

  @override
  String get description => 'List tickets and their descriptions';

  @override
  Future<void> run() async {
    // Tickets sit directly in the workspace root; a legacy `tickets` folder
    // is still read.
    final subs = WorkspaceUtils.ticketDirs(workspacePath);
    if (subs.isEmpty) {
      ggLog(cDetail('No tickets found.'));
      return;
    }
    for (final d in subs) {
      final ticketName = path.basename(d.path);
      // The ticket.json is what made the folder a ticket in the first place,
      // so it is there — only its content can still disappoint.
      final ticketFile = File(path.join(d.path, ticketJsonFileName));
      try {
        final content = ticketFile.readAsStringSync();
        final data = jsonDecode(content) as Map<String, dynamic>;
        final desc = data['description'] as String? ?? '';
        ggLog('$ticketName    $desc'); // four spaces between name and desc
      } catch (e) {
        ggLog(cError('Error parsing ticket.json for ticket $ticketName: $e'));
      }
    }
  }
}
