// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as path;

import 'package:gg_multi_core/gg_multi_core.dart';

/// Command that executes a shell command in all repositories of the
/// current ticket in the order of the processing list.
class DoExecuteCommand extends DirCommand<void> {
  /// Constructor
  DoExecuteCommand({
    required super.ggLog,
    super.name = 'cmd',
    super.description = 'Run a shell command in all ticket repos',
    SortedProcessingList? sortedProcessingList,
    ProcessRunner? processRunner,
  }) : _sortedProcessingList =
           sortedProcessingList ?? SortedProcessingList(ggLog: ggLog),
       _processRunner = processRunner ?? defaultProcessRunner {
    _addArgs();
  }

  /// Sorted processing helper
  final SortedProcessingList _sortedProcessingList;

  /// The process runner used to execute commands
  final ProcessRunner _processRunner;

  @override
  Future<void> exec({
    required Directory directory,
    required GgLog ggLog,
    Map<String, dynamic> options = const {},
  }) => get(directory: directory, ggLog: ggLog);

  @override
  Future<void> get({required Directory directory, required GgLog ggLog}) async {
    // Validate command arguments
    final rest = argResults?.rest ?? [];
    if (rest.isEmpty) {
      throw UsageException('Missing command parameter.', usage);
    }
    final cmd = rest.first;
    final cmdArgs = rest.sublist(1);

    // Detect ticket folder
    final String? ticketPath = WorkspaceUtils.detectTicketPath(
      path.absolute(directory.path),
    );
    if (ticketPath == null) {
      ggLog(cAction('Please run this command inside a ticket folder.'));
      throw Exception(cDetail('Not inside a ticket folder'));
    }

    final ticketDir = Directory(ticketPath);
    final ticketName = path.basename(ticketDir.path);

    // Collect repositories in processing order
    final nodes = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );

    if (nodes.isEmpty) {
      ggLog(cWarn('⚠️ No repos in this ticket'));
      return;
    }

    final failed = <String>[];

    for (final node in nodes) {
      final repoDir = node.directory;
      final repoName = path.basename(repoDir.path);

      ggLog('\n${cH1(repoName)}');

      final result = await _processRunner(
        cmd,
        cmdArgs,
        workingDirectory: repoDir.path,
      );

      if (result.exitCode != 0) {
        final stderrStr = result.stderr?.toString() ?? '';
        final stdoutStr = result.stdout?.toString() ?? '';
        final errMsg = stderrStr.isNotEmpty ? stderrStr : stdoutStr;
        ggLog(
          [
            cDetail('✗ Failed to execute'),
            cError(rmControls(errMsg)),
          ].join('\n'),
        );
        failed.add(repoName);
      }
    }

    if (failed.isEmpty) {
      ggLog('\nCommand executed in all repos of $ticketName\n');
      return;
    }

    ggLog(cAction('\nPlease fix the issues above.\n'));
    throw Exception(cDetail('Failed to execute the command.'));
  }

  /// Add passthrough flag so args like -l 120 don't break parsing.
  void _addArgs() {
    // Accept a common formatting length flag used by tests so that
    // command line parsing does not fail before forwarding to the
    // real tool. We don't use it here - it is consumed by the tool
    // we invoke (e.g. `dart fmt -l 120`).
    argParser.addOption(
      'line-length',
      abbr: 'l',
      help: 'Passthrough. Ignored by this command.',
    );
  }
}
