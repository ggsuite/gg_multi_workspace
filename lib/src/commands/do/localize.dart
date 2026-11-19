// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_multi_core/gg_multi_core.dart';
import 'package:path/path.dart' as path;

/// Localizes the references between the repositories of the current ticket:
/// only out-of-sync repos are touched, gg's changes become `#gg:` commits.
/// The ocean repos between a ticket repo and a recorded release that breaks
/// its dependents are added to the ticket first with [AddReposBetween], when
/// it is handed over; other missing repos are only warned about.
class DoLocalizeCommand extends DirCommand<void> {
  /// Constructor.
  DoLocalizeCommand({
    required super.ggLog,
    super.name = 'localize',
    super.description = 'Localize the references between the ticket repos',
    SortedProcessingList? sortedProcessingList,
    TicketLocalizer? ticketLocalizer,
    AddReposBetween? addReposBetween,
  }) : _sortedProcessingList =
           sortedProcessingList ?? SortedProcessingList(ggLog: ggLog),
       _ticketLocalizer = ticketLocalizer ?? TicketLocalizer(ggLog: ggLog),
       _addBetween = addReposBetween;

  // ...........................................................................
  @override
  Future<void> exec({
    required Directory directory,
    required GgLog ggLog,
    Map<String, dynamic> options = const {},
  }) => get(directory: directory, ggLog: ggLog);

  // ...........................................................................
  @override
  Future<void> get({required Directory directory, required GgLog ggLog}) async {
    final ticketPath = WorkspaceUtils.detectTicketPath(
      path.absolute(directory.path),
    );
    if (ticketPath == null) {
      throw UsageException(
        'gg do localize only works inside a ticket folder.',
        usage,
      );
    }

    final ticketDir = Directory(ticketPath);

    // A breaking release brings the repos between into the ticket first.
    await _ticketLocalizer.addMissingBetween(
      ticketDir: ticketDir,
      addReposBetween: _addBetween,
      ggLog: ggLog,
    );

    final nodes = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );
    if (nodes.isEmpty) {
      ggLog(cWarn('⚠️ No repos in this ticket'));
      return;
    }

    // Other missing repos are only warned about.
    final localized = await _ticketLocalizer.localizeUnlocalized(
      ticketDir: ticketDir,
      repos: nodes,
      ggLog: ggLog,
    );
    if (localized.isEmpty) {
      ggLog(cDetail('✓ All references are already localized.'));
    }
  }

  // ######################
  // Private
  // ######################

  /// Lists the ticket repos in dependency order.
  final SortedProcessingList _sortedProcessingList;

  /// Checks, localizes and commits the references of the ticket repos.
  final TicketLocalizer _ticketLocalizer;

  /// Adds the repos a breaking release strands; null adds none.
  final AddReposBetween? _addBetween;
}

/// Mock for [DoLocalizeCommand].
class MockDoLocalizeCommand extends MockDirCommand<void>
    implements DoLocalizeCommand {}
