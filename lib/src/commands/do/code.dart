// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as p;
import 'package:path/path.dart' as path;

import 'package:gg_multi_core/gg_multi_core.dart';
import 'package:gg_multi_workspace/src/backend/vscode_launcher.dart';

/// Command to open all repos (or a single repo) under a ticket in VS Code.
class CodeCommand extends Command<void> {
  /// Constructor.
  CodeCommand({
    required this.ggLog,
    String? rootPath,
    String? executionPath,
    DirectoryFactory? directoryFactory,
    VSCodeLauncher? launcher,
    SortedProcessingList? sortedProcessingList,
    // coverage:ignore-start
  }) : workspacePath = rootPath ?? WorkspaceUtils.defaultGgMultiWorkspacePath(),
       _executionPath = executionPath ?? Directory.current.path,
       _dirFactory = directoryFactory ?? Directory.new,
       _launcher = launcher ?? VSCodeLauncher();
  // coverage:ignore-end

  /// The log function.
  final GgLog ggLog;

  /// Gg Multi workspace path.
  final String workspacePath;

  /// The path from which the command is executed.
  final String _executionPath;

  /// Used for test injection.
  final DirectoryFactory _dirFactory;

  /// Responsible for launching VS Code.
  final VSCodeLauncher _launcher;

  String _rel(String absPath) => p.relative(absPath, from: _executionPath);

  @override
  String get name => 'code';

  @override
  String get description => 'Open a ticket or a single repo in VS Code';

  @override
  Future<void> run() async {
    final args = argResults!.rest;

    // No explicit target, try to detect ticket from execution path.
    if (args.isEmpty) {
      final ticketPath = WorkspaceUtils.detectTicketPath(_executionPath);
      if (ticketPath == null) {
        throw UsageException('Missing ticket parameter.', usage);
      }

      final ticketDir = Directory(ticketPath);
      await _openTicketWorkspace(ticketDir);
      return;
    }

    // One trailing separator is what a tab completion leaves (`T1/`).
    final target = WorkspaceUtils.normalizeTicketName(args.first);
    final parts = target.split(RegExp(r'[\\/]'));
    if (parts.isEmpty || parts.length > 2) {
      throw UsageException(
        'Invalid target format. Use <ticket> or <ticket>/<repo>.',
        usage,
      );
    }

    final ticketName = parts[0];
    final repoName = parts.length == 2 ? parts[1] : null;

    // A name that is no ticket name — empty, hidden, `tickets` — is named as
    // such before it is joined to the workspace root.
    final nameError = WorkspaceUtils.ticketNameError(ticketName);
    if (nameError != null) {
      ggLog(cError(nameError));
      return;
    }

    // Tickets sit directly in the workspace root; a legacy `tickets` folder
    // is still resolved. Only a real ticket is opened — never a plain folder
    // such as `doc` that merely has the name.
    final existing = WorkspaceUtils.existingTicketDir(
      rootPath: workspacePath,
      ticketName: ticketName,
    );

    if (existing == null) {
      final place = path.join(workspacePath, ticketName);
      if (FileSystemEntity.typeSync(place, followLinks: false) !=
          FileSystemEntityType.notFound) {
        ggLog(
          cError(
            '$ticketName is no ticket: ${_rel(place)} holds no '
            '$ticketJsonFileName.',
          ),
        );
      } else {
        ggLog(cError('Ticket $ticketName not found at ${_rel(place)}'));
      }
      return;
    }

    final ticketDir = _dirFactory(existing.path);

    if (repoName != null) {
      // The repo is looked up in the whole ticket, so `<ticket>/<repo>` finds
      // it inside its organization folder too.
      final repoDir =
          RepoFolderResolver.resolve(
            workspacePath: ticketDir.path,
            repoName: repoName,
          ) ??
          Directory(path.join(ticketDir.path, repoName));
      if (!repoDir.existsSync()) {
        ggLog(
          cError(
            'Repository $repoName not found '
            'in ticket $ticketName at ${_rel(repoDir.path)}',
          ),
        );
        return;
      }
      await _openInVSCode(repoDir);
    } else {
      await _openTicketWorkspace(ticketDir);
    }
  }

  /// Opens the VS Code workspace file `<ticket_name>.code-workspace` that
  /// belongs to [ticketDir]. The file does not need to exist yet; VS Code
  /// can create it on demand.
  Future<void> _openTicketWorkspace(Directory ticketDir) async {
    final ticketName = path.basename(ticketDir.path);
    final workspacePath = path.join(
      ticketDir.path,
      '$ticketName.code-workspace',
    );

    await _launcher.openPath(workspacePath);
    ggLog(cDetail('✓ Opened workspace $ticketName.code-workspace'));
  }

  Future<void> _openInVSCode(Directory dir) async {
    await _launcher.openDirectory(dir);
    ggLog(cDetail('✓ Opened ${path.basename(dir.path)} at ${_rel(dir.path)}'));
  }
}

/// Typedef for creating Directory instances (for testing).
typedef DirectoryFactory = Directory Function(String path);
