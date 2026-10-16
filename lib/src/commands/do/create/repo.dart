// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/args.dart';
import 'package:gg_create_repo/gg_create_repo.dart';
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
    return WorkspaceRepoHost(
      executionPath: executionPath,
      oceanPath: WorkspaceUtils.defaultOceanWorkspacePath(
        workingDir: executionPath,
      ),
      addToTicket: args['add'] as bool,
      add: addToTicket,
    );
  }
}
