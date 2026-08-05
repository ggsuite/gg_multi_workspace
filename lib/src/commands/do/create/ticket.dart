// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as p;
import 'package:path/path.dart' as path;

import 'package:gg_multi_core/gg_multi_core.dart';
import 'package:gg_multi_workspace/src/backend/repo_setup.dart';

/// Typedef for creating Directory instances (for testing).
typedef DirectoryFactory = Directory Function(String path);

/// Command to create a ticket folder and save ticket data as JSON.
class TicketCommand extends DirCommand<void> {
  /// Constructor with optional workspace [rootPath] and [directoryFactory].
  TicketCommand({
    required super.ggLog,
    String? rootPath,
    DirectoryFactory? directoryFactory,
    super.name = 'ticket',
    super.description = 'Create a ticket folder with its ticket data',
    // coverage:ignore-start
  }) : rootPath = rootPath ?? WorkspaceUtils.defaultGgMultiWorkspacePath(),
       directoryFactory = directoryFactory ?? Directory.new
  // coverage:ignore-end
  {
    // The ticket message
    argParser.addOption(
      'message',
      abbr: 'm',
      help: 'Ticket description.',
      mandatory: true,
    );
  }

  /// Base path that contains the `tickets` folder.
  final String rootPath;

  /// Factory to create Directory instances
  final DirectoryFactory directoryFactory;

  @override
  Future<void> exec({required Directory directory, required GgLog ggLog}) =>
      get(directory: directory, ggLog: ggLog);

  @override
  Future<void> get({required Directory directory, required GgLog ggLog}) async {
    // Validate issue id ------------------------------------------------------
    if (argResults!.rest.isEmpty) {
      throw UsageException('Missing issue id parameter.', usage);
    }

    final issueId = argResults!.rest.first;

    // The description might be null if the user did not pass --message / -m.
    final String description = (argResults!['message'] as String?) ?? '';

    // Build the directory path for the ticket (always under the workspace
    // root, independent from the execution directory).
    final ticketsPath = path.join(rootPath, ggMultiTicketFolder, issueId);
    final dir = directoryFactory(ticketsPath);
    final ticketFile = File(path.join(ticketsPath, '.ticket'));

    final relPath = p.relative(ticketsPath, from: directory.path);

    if (dir.existsSync() && ticketFile.existsSync()) {
      ggLog(
        cError(
          'Error: Ticket $issueId already exists at '
          '$relPath',
        ),
      );
      return;
    }

    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    // Write the .ticket file as JSON.
    writeRootTicket(
      Directory(ticketsPath),
      issueId: issueId,
      description: description,
    );

    // Write the VS Code workspace so `do code <ticket>` opens the fresh
    // ticket right away. It holds the ticket folder itself until `do add`
    // rewrites it with one entry per repository.
    writeCodeWorkspaceFile(Directory(ticketsPath), const <String>[]);

    // Every ticket gets its trash folder right away, so `do publish` has a
    // place to move the ticket's repos to and the user can find it even
    // before anything was removed.
    Trash.createDirForTicket(Directory(ticketsPath));

    ggLog(cSuccess('✓ Created ticket $issueId'));

    ggLog(cAction('  Please run:'));

    ggLog(cCmd('    cd $relPath'));

    ggLog(cCmd('    gg do add <repo1> <repo2> ...'));

    ggLog(cCmd('    code $issueId.code-workspace'));
  }
}
