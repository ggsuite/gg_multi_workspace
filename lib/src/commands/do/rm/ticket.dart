// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_git/gg_git.dart';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;

import 'package:gg_multi_core/gg_multi_core.dart';

/// Closes one or more tickets: deletes the remote feature branches of their
/// repositories and moves each whole ticket — repositories as they are, plus
/// `ticket.json`, `.gg/` and the `.code-workspace` file — to
/// `<root>/.trash/<ticket>`.
///
/// The tickets to close are named as arguments (`gg do rm ticket 88 92`).
/// Without arguments the ticket of the current working directory is taken —
/// running the command inside a ticket needs no name. When neither applies,
/// the command explains both ways instead of guessing.
///
/// This is the explicit counterpart of the offer `gg multi do publish` makes
/// up front: keep working for now, close the ticket later with this command.
/// Nothing is deleted outright — the trash keeps everything recoverable,
/// uncommitted leftovers included.
///
/// `--no-delete-remote-branch` keeps the remote branches; the ticket folders
/// move to the trash either way.
class RemoveTicketCommand extends Command<void> {
  /// Constructor.
  RemoveTicketCommand({
    required this.ggLog,
    String? rootPath,
    ProcessRunner? processRunner,
    // coverage:ignore-start
  }) : rootPath = rootPath ?? Directory.current.path,
       // coverage:ignore-end
       _processRunner = processRunner {
    argParser.addFlag(
      'delete-remote-branch',
      defaultsTo: true,
      help: 'Delete the remote feature branch of every ticket repo.',
    );
  }

  // ...........................................................................
  @override
  String get name => 'ticket';

  // ...........................................................................
  @override
  String get description =>
      'Move tickets to the trash and delete their remote branches';

  // ...........................................................................
  @override
  String get invocation => 'gg do rm ticket [<ticket-id>...]';

  // ...........................................................................
  @override
  Future<void> run() async {
    final ticketDirs = _resolveTicketDirs();
    final deleteRemoteBranch = argResults!['delete-remote-branch'] as bool;

    for (final ticketDir in ticketDirs) {
      // With more than one ticket the name has to lead its output, else the
      // messages of the second ticket read like a continuation of the first.
      if (ticketDirs.length > 1) {
        ggLog('\n${cH1(path.basename(ticketDir.path))}');
      }

      await cleanUpTicket(
        ticketDir: ticketDir,
        repoDirs: RepoFolderResolver.repoDirs(ticketDir.path),
        deleteRemoteBranch: deleteRemoteBranch,
        ggLog: ggLog,
        taskLog: ggLog,
        processRunner: _processRunner,
      );
    }
  }

  /// Log sink.
  final GgLog ggLog;

  /// Directory the command was invoked in.
  final String rootPath;

  /// Runs git (injectable for tests); null falls back to the real runner.
  final ProcessRunner? _processRunner;

  // ######################
  // Private
  // ######################

  // ...........................................................................
  /// The ticket folders to close: the named ones, or the one the command was
  /// invoked in when no name was given.
  List<Directory> _resolveTicketDirs() {
    final names = argResults!.rest;
    if (names.isEmpty) {
      return <Directory>[_ticketDirOfCwd()];
    }

    // The workspace root is resolved from the working directory, so naming a
    // ticket works from anywhere inside the workspace — also from within
    // another ticket.
    final workspacePath = WorkspaceUtils.defaultGgMultiWorkspacePath(
      workingDir: rootPath,
    );
    final dirs = <Directory>[];
    final missing = <String>[];
    for (final name in names) {
      final dir = WorkspaceUtils.ticketDir(
        rootPath: workspacePath,
        ticketName: name,
      );
      if (dir.existsSync()) {
        dirs.add(dir);
      } else {
        missing.add(name);
      }
    }

    if (missing.isNotEmpty) {
      throw Exception(
        cError(
          'These tickets do not exist in $workspacePath: '
          '${missing.join(', ')}.',
        ),
      );
    }

    return dirs;
  }

  // ...........................................................................
  /// The ticket the command was invoked in, or an error naming both ways to
  /// address a ticket.
  Directory _ticketDirOfCwd() {
    final ticketPath = WorkspaceUtils.detectTicketPath(rootPath);
    if (ticketPath == null) {
      throw Exception(
        cError(
          '»gg do rm ticket« needs a ticket: either call it inside a ticket '
          'folder, or name the tickets to remove — '
          '${cCmd('gg do rm ticket <ticket-id>...')}.',
        ),
      );
    }
    return Directory(ticketPath);
  }
}
