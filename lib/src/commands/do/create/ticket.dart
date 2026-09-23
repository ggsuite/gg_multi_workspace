// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
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

  /// The workspace root the ticket folder is created in, beside `.ocean`.
  final String rootPath;

  /// Factory to create Directory instances
  final DirectoryFactory directoryFactory;

  @override
  Future<void> exec({
    required Directory directory,
    required GgLog ggLog,
    Map<String, dynamic> options = const {},
  }) => get(directory: directory, ggLog: ggLog);

  @override
  Future<void> get({required Directory directory, required GgLog ggLog}) async {
    // Validate issue id ------------------------------------------------------
    if (argResults!.rest.isEmpty) {
      throw UsageException('Missing issue id parameter.', usage);
    }

    // One trailing separator is what a tab completion leaves (`T1/`).
    final issueId = WorkspaceUtils.normalizeTicketName(argResults!.rest.first);

    // A ticket is named by one visible folder name: no path, nothing hidden,
    // not the legacy `tickets` folder.
    final nameError = WorkspaceUtils.ticketNameError(issueId);
    if (nameError != null) {
      throw UsageException(nameError, usage);
    }

    // The description might be null if the user did not pass --message / -m.
    final String description = (argResults!['message'] as String?) ?? '';

    // The ticket is created directly in the workspace root, independent from
    // the execution directory. An existing ticket, or anything else that
    // already has that name there — the `doc`, `dna` or `scripts` folder of
    // the DNA, a file, a folder of the user — makes this throw.
    final ticketDir = directoryFactory(
      WorkspaceUtils.newTicketDir(
        rootPath: rootPath,
        ticketName: issueId,
        relativeTo: directory.path,
      ).path,
    );
    final relPath = path.relative(ticketDir.path, from: directory.path);

    // Write the ticket.json. It carries the ticket id and its description
    // from the very first moment; `do add` later fills in the repositories.
    writeTicketJson(
      ticketDir,
      TicketJson(
        issueId: issueId,
        description: description,
        repositories: const <TicketRepo>[],
        ggVersion: ggCliVersion,
      ),
    );

    // Write the VS Code workspace so `do code <ticket>` opens the fresh
    // ticket right away. It holds the ticket folder itself until `do add`
    // rewrites it with one entry per repository.
    writeCodeWorkspaceFile(ticketDir, const <String>[]);

    // Creating a ticket is the moment the workspace is touched as a whole,
    // so it is where the trash is swept: everything that has been lying in
    // it for `Trash.maxAge` goes. Best-effort — a workspace that cannot be
    // cleaned still gets its ticket.
    await _expireTrash(ticketDir);

    // Every ticket gets its trash folder right away, so `do publish` has a
    // place to move the ticket's repos to and the user can find it even
    // before anything was removed.
    Trash.createDirForTicket(ticketDir);

    ggLog(cSuccess('✓ Created ticket $issueId'));

    ggLog(cAction('  Please run:'));

    ggLog(cCmd('    cd $relPath'));

    ggLog(cCmd('    gg do add <repo1> <repo2> ...'));

    ggLog(cCmd('    code $issueId.code-workspace'));
  }

  // ...........................................................................
  /// Drops the trash entries of the workspace holding [ticketDir] that are
  /// older than [Trash.maxAge] and reports how many went.
  ///
  /// Nothing here may cost the user their ticket: a trash that cannot be
  /// read or written — a locked folder, a read-only volume — is reported
  /// and left to the next run.
  Future<void> _expireTrash(Directory ticketDir) async {
    try {
      final removed = await Trash.expire(
        rootPath: WorkspaceUtils.rootOfTicket(ticketDir),
      );
      if (removed.isNotEmpty) {
        ggLog(
          cDetail(
            '✓ Emptied ${removed.length} trash '
            '${removed.length == 1 ? 'entry' : 'entries'} older than '
            '${Trash.maxAge.inDays} days',
          ),
        );
      }
    } on Object catch (e) {
      ggLog(cWarn('⚠️ Could not empty the trash: $e'));
    }
  }
}
