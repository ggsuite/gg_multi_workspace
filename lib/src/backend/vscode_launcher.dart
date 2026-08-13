// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_process/gg_process.dart';

/// Typedef for launching a process, mainly for testability.
typedef ProcessStarter =
    Future<void> Function(
      String executable,
      List<String> arguments, {
      bool runInShell,
    });

/// Provides logic to open a directory or workspace file in VS Code via
/// the command line.
///
/// Example:
/// ```dart
/// final launcher = VSCodeLauncher();
/// await launcher.openDirectory(Directory('/some/path'));
/// await launcher.openPath('/some/path/my.code-workspace');
/// ```
class VSCodeLauncher {
  /// Constructs a VSCodeLauncher with optional [processStarter] injection.
  /// The default starts VS Code using [GgProcessDelegate.current] with
  /// `runInShell: true`.
  VSCodeLauncher({ProcessStarter? processStarter})
    : _starter = processStarter ?? _defaultStarter;

  final ProcessStarter _starter;

  /// Opens the given [directory] in VS Code via CLI.
  ///
  /// This is kept for backwards compatibility and simply delegates to
  /// [openDirectory].
  Future<void> open(Directory directory) => openDirectory(directory);

  /// Opens the given [directory] in VS Code via CLI.
  /// Throws any exception from process launching.
  Future<void> openDirectory(Directory directory) {
    return _starter('code', [directory.path], runInShell: true);
  }

  /// Opens an arbitrary VS Code target [path] (for example a
  /// `<ticket>.code-workspace` file) via CLI.
  /// Throws any exception from process launching.
  Future<void> openPath(String path) {
    return _starter('code', [path], runInShell: true);
  }

  // Real implementation for launching VS Code.
  // coverage:ignore-start
  static Future<void> _defaultStarter(
    String executable,
    List<String> arguments, {
    bool runInShell = false,
  }) async {
    // Detached: VS Code keeps running after gg exits, and — the reason it
    // matters here — its stdio is not connected to our terminal. An attached
    // `code` writes into the same line gg just printed and cuts the
    // confirmation in half.
    await ggStartProcess(
      executable,
      arguments,
      runInShell: runInShell,
      mode: ProcessStartMode.detached,
    );
  }

  // coverage:ignore-end
}
