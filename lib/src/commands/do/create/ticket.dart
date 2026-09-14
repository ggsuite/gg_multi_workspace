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

    final issueId = argResults!.rest.first;

    // A hidden folder is never a ticket, so a ticket created under such a
    // name would be invisible to every other command.
    if (WorkspaceUtils.isHiddenName(issueId)) {
      throw UsageException(
        'The issue id "$issueId" starts with a dot, '
        'but hidden folders are never tickets.',
        usage,
      );
    }

    // `tickets` is the folder older gg versions kept their tickets in; a
    // ticket of that name would make its repositories look like tickets.
    if (issueId == ggMultiLegacyTicketFolder) {
      throw UsageException(
        'The issue id "$issueId" is reserved for the folder older gg '
        'versions kept their tickets in.',
        usage,
      );
    }

    // The description might be null if the user did not pass --message / -m.
    final String description = (argResults!['message'] as String?) ?? '';

    // A ticket of that name — in the root or in a legacy `tickets` folder —
    // is reported, never written into again.
    final existing = WorkspaceUtils.existingTicketDir(
      rootPath: rootPath,
      ticketName: issueId,
    );
    if (existing != null) {
      ggLog(
        cError(
          'Error: Ticket $issueId already exists at '
          '${p.relative(existing.path, from: directory.path)}',
        ),
      );
      return;
    }

    // The ticket is created directly in the workspace root, independent from
    // the execution directory. Whatever else already has that name there —
    // the `doc`, `dna` or `scripts` folder of the DNA, a file, a folder of the
    // user — is never taken over.
    final ticketsPath = path.join(rootPath, issueId);
    final relPath = p.relative(ticketsPath, from: directory.path);
    if (FileSystemEntity.typeSync(ticketsPath, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw Exception(
        cError(
          '$relPath already exists and is no ticket. '
          'Choose another issue id.',
        ),
      );
    }

    directoryFactory(ticketsPath).createSync(recursive: true);

    // Write the ticket.json. It carries the ticket id and its description
    // from the very first moment; `do add` later fills in the repositories.
    writeTicketJson(
      Directory(ticketsPath),
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
