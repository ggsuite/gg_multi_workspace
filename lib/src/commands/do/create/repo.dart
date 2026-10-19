// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_create_repo/gg_create_repo.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_multi_core/gg_multi_core.dart';

import '../../../backend/workspace_repo_host.dart';

/// `gg do create repo`: creates a repository in the ocean of the workspace
/// and, inside a ticket, adds it to the ticket. Outside of a workspace it
/// creates the repository in the folder given with `--output`.
class RepoCommand extends CreateRepo {
  /// Constructor
  RepoCommand({
    required super.ggLog,
    String? executionPath,
    AddToTicket? addToTicket,
    super.collector,
    super.preflight,
    super.creator,
    super.prompts,
  }) : super(
         name: 'repo',
         description:
             'Create a new Dart or TypeScript repository in the ocean and '
             'add it to the current ticket.',
         host: (args) => hostFor(
           args,
           executionPath:
               executionPath ?? Directory.current.path, // coverage:ignore-line
           addToTicket: addToTicket,
         ),
       ) {
    argParser.addFlag(
      'add',
      defaultsTo: true,
      help: 'Inside a ticket: add the new repository to the ticket.',
    );
  }

  // ...........................................................................
  /// The workspace host inside a workspace, else the standalone host.
  static RepoHost hostFor(
    ArgResults args, {
    required String executionPath,
    AddToTicket? addToTicket,
  }) {
    if (!WorkspaceUtils.isInsideExistingWorkspace(executionPath)) {
      return CreateRepo.standaloneHost(args);
    }
    if (args.wasParsed('output')) {
      throw Exception(
        cError(
          '--output is only for use outside of a workspace; inside one the '
          'repo goes to .ocean/<org>/<name>.',
        ),
      );
    }
    return WorkspaceRepoHost(
      executionPath: executionPath,
      oceanPath: WorkspaceUtils.defaultOceanWorkspacePath(
        workingDir: executionPath,
      ),
      addToTicket: args['add'] as bool,
      add: addToTicket,
    );
  }

  // ...........................................................................
  /// A command outside of any workspace; tests pass what they care about.
  factory RepoCommand.example({
    GgLog? ggLog,
    String? executionPath,
    AddToTicket? addToTicket,
    SpecCollector? collector,
    Preflight? preflight,
    RepoCreator? creator,
  }) => RepoCommand(
    ggLog: ggLog ?? (_) {},
    executionPath: executionPath ?? Directory.systemTemp.path,
    addToTicket: addToTicket,
    collector: collector,
    preflight: preflight,
    creator: creator,
  );
}
