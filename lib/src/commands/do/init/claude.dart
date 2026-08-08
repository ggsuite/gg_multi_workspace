// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as path;

import 'package:gg_multi_core/gg_multi_core.dart';

/// Creates a ticket-level CLAUDE.md file from all repositories in a ticket.
class DoClaudeCommand extends DirCommand<void> {
  /// Creates a new claude command.
  DoClaudeCommand({
    required super.ggLog,
    super.name = 'claude',
    super.description = 'Create a ticket-level CLAUDE.md',
    SortedProcessingList? sortedProcessingList,
  }) : _sortedProcessingList =
           sortedProcessingList ?? SortedProcessingList(ggLog: ggLog);

  /// Provides repositories in dependency order.
  final SortedProcessingList _sortedProcessingList;

  @override
  Future<void> exec({
    required Directory directory,
    required GgLog ggLog,
    Map<String, dynamic> options = const {},
  }) => get(directory: directory, ggLog: ggLog);

  @override
  Future<void> get({required Directory directory, required GgLog ggLog}) async {
    final String? ticketPath = WorkspaceUtils.detectTicketPath(
      path.absolute(directory.path),
    );
    if (ticketPath == null) {
      ggLog(cAction('Please run this command inside a ticket folder.'));
      throw Exception(cDetail('Not inside a ticket folder'));
    }

    final ticketDir = Directory(ticketPath);

    final nodes = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );

    await GgStatusPrinter<void>(
      message: 'Creating CLAUDE.md',
      ggLog: ggLog,
      dark: true,
    ).run(() async => _writeClaudeFile(ticketDir: ticketDir, nodes: nodes));

    ggLog(cAction('Execute claude code with:\n') + cCmd('claude'));
  }

  /// Writes the aggregated CLAUDE.md file into [ticketDir].
  Future<void> _writeClaudeFile({
    required Directory ticketDir,
    required List<Node> nodes,
  }) async {
    final buffer = StringBuffer()
      ..writeln(claudeClaudeMd)
      ..writeln('## Workspace Overview')
      ..writeln()
      ..writeln('- Ticket workspace: ${path.basename(ticketDir.path)}')
      ..writeln('- Repository count: ${nodes.length}')
      ..writeln()
      ..writeln(claudeCommands)
      ..writeln('## Architecture')
      ..writeln();

    for (final node in nodes) {
      final repoDir = node.directory;
      final packageName = path.basename(repoDir.path);
      final claudeFile = File(path.join(repoDir.path, 'CLAUDE.md'));
      final architectureContent = await _readArchitectureContent(
        claudeFile: claudeFile,
        repoName: packageName,
      );

      buffer
        ..writeln('### $packageName Architecture')
        ..writeln(
          '<!-- Begin Content CLAUDE.md '
          'inside repo $packageName -->',
        )
        ..writeln(architectureContent)
        ..writeln(
          '<!-- End Content CLAUDE.md '
          'inside repo $packageName -->',
        )
        ..writeln();
    }

    buffer.writeln(claudeCodeStandards);

    final ticketClaudeFile = File(path.join(ticketDir.path, 'CLAUDE.md'));
    await ticketClaudeFile.writeAsString(buffer.toString());
  }

  /// Reads the repository CLAUDE.md content or throws when it is missing.
  Future<String> _readArchitectureContent({
    required File claudeFile,
    required String repoName,
  }) async {
    if (!claudeFile.existsSync()) {
      throw Exception(
        cError(
          'Please start claude and run /init in the repo $repoName. '
          'Then execute this command again.',
        ),
      );
    }

    final content = await claudeFile.readAsString();
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return 'CLAUDE.md is empty in this repository.';
    }

    return trimmed;
  }
}

/// Mock for [DoClaudeCommand]
class MockDoClaudeCommand extends MockDirCommand<void>
    implements DoClaudeCommand {}

/// Begin of generated CLAUDE.md
const String claudeClaudeMd = '''
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.
''';

/// command instructions to be included in generated CLAUDE.md
const String claudeCommands = '''
## Commands

These commands are available in the ticket workspace and in the single repositories:

```bash
gg do add <repo> [<repo2> ...] # add repos to the ticket workspace given by their names
gg can commit # run all checks in all repos (analyze + format + tests)
gg do commit -m <message> # commit in all repos after checks pass
gg can push # check for all repos if they are ready to push (checks + commit)
gg do push # merge main into the feature branches and push all repos
gg do review # push all repos (incl. main merge) and open the pull requests
gg did review # check whether the current ticket state was reviewed
gg do publish # publish all repos after review is approved (should be executed manually by a human)
```

To install gg, run:
```bash
dart pub global activate gg
```

The following commands are only available in the repositories in the ticket workspace:

### GG One Commands (gg one is often used by gg commands)
```bash
gg one check analyze             # static analysis
gg one check format              # formatting check
gg one can commit                # run all checks (analyze + format + tests)
gg one do commit -m <message>    # commit after checks pass
gg one do push                   # push after checks pass
```

### Testing
```bash
dart test                        # run all tests
dart test test/path/to/file_test.dart  # run a single test file
```

### get dependencies
```bash
dart pub get
```

For committing, always use gg one do commit or gg do commit.
For pushing, always use gg one do push or gg do push.

''';

/// code standards to be included in generated CLAUDE.md
const String claudeCodeStandards = '''
## Code Standards

- **Line length**: 80 characters maximum
- **Quotes**: Single quotes required (`prefer_single_quotes`)
- **Trailing commas**: Required in parameter/argument lists
- **Return types**: Always declared explicitly
- **Public API docs**: All public members require dartdoc comments
- **Strict analyzer**: `strict-casts`, `strict-inference`, `strict-raw-types` all enabled
- **Test coverage**: 100% required. Use `// coverage:ignore-line` / `// coverage:ignore-start` / `// coverage:ignore-end` only when truly necessary.

Each source file in `lib/src/` must have a corresponding test file in `test/` at the same relative path.

''';
