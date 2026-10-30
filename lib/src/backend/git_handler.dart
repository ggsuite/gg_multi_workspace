// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_git/gg_git.dart';

import 'dart:async';
import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_one/gg_one.dart' as gg;
import 'package:gg_process/gg_process.dart';

/// Thrown when a clone failed because ssh is not set up for the host yet:
/// the host is unknown, its key changed or it refused the user's key.
class SshSetupException implements Exception {
  /// Constructor
  SshSetupException(this.message, {this.host});

  /// What went wrong and what the developer does next.
  final String message;

  /// The ssh host, as known_hosts names it, when the url names one.
  final String? host;

  @override
  String toString() => 'Exception: $message';
}

/// Typedef for a process runner function.
/// A class responsible for cloning git repositories and performing Git/utility operations.
class GitHandler {
  /// The function used to run system processes.
  final ProcessRunner processRunner;

  /// Constructor accepts an optional [processRunner]
  /// to enable testing by injection.
  ///
  /// The network commands (clone, ls-remote) are retried by [gitRetry] when
  /// the remote drops the connection; [ggLog] receives the notice of a retry.
  ///
  /// A clone that fails because ssh does not know the host yet shows the
  /// key the host presents and asks on the terminal whether to trust it.
  /// [sshHostKeys] reads and stores the key, `prompts` asks the question —
  /// [gg.GgPrompts.current] by default — and `hasTerminal` tells whether
  /// anybody can answer.
  GitHandler({
    ProcessRunner? processRunner,
    GgLog? ggLog,
    this._gitRetry = const GitRetry(),
    SshHostKeys? sshHostKeys,
    this._prompts,
    this._hasTerminal = gg.stdioHasTerminal,
  }) : processRunner = processRunner ?? ggRunProcess,
       _ggLog = ggLog ?? _silent,
       _sshHostKeys =
           sshHostKeys ??
           SshHostKeys(processRunner: processRunner ?? ggRunProcess);

  final GgLog _ggLog;
  final GitRetry _gitRetry;
  final SshHostKeys _sshHostKeys;
  final gg.GgPrompts? _prompts;
  final gg.HasTerminal _hasTerminal;

  /// The answer of the user per host, asked once per run: parallel clones
  /// of the same host wait for the one question, and a declined host is not
  /// asked about again.
  final _hostTrust = <String, Future<bool>>{};

  /// The last dialog of the run. Clones of different hosts run in parallel
  /// too, and their dialogs must not share the terminal at the same time.
  Future<void> _lastDialog = Future<void>.value();

  static void _silent(String message) {}

  /// Clones the repository from [repoUrl] into [targetDirectory].
  /// Throws an exception if cloning fails.
  Future<void> cloneRepo(String repoUrl, String targetDirectory) async {
    // Ensure the parent directory exists. A clone that fails must not leave
    // the folders behind that were created for it, so the outermost folder
    // created here is remembered and removed again below.
    final directory = Directory(targetDirectory);
    final createdRoot = _createParentDirectories(directory);

    // Run the git clone command using the injected process runner.
    Future<ProcessResult> clone() => _gitRetry.run(
      () => processRunner('git', <String>['clone', repoUrl, targetDirectory]),
      ggLog: _ggLog,
      description: 'git clone $repoUrl',
    );

    var result = await clone();
    final keyAdded =
        result.exitCode != 0 &&
        await _trustUnknownHost(repoUrl, '${result.stderr}');
    if (keyAdded) {
      result = await clone();
    }

    if (result.exitCode != 0) {
      _removeLeftovers(target: directory, createdRoot: createdRoot);

      final stderr = '${result.stderr}'.trim();
      final failure = 'Failed to clone repo from $repoUrl: $stderr';
      final hint = SshHostKeys.setupHint(
        repoUrl,
        stderr,
        keyAddedTo: keyAdded ? _sshHostKeys.knownHostsPath : null,
      );
      if (hint != null) {
        throw SshSetupException(
          cError('$failure\n$hint'),
          host: SshHostKeys.hostOf(repoUrl),
        );
      }
      throw Exception(cError(failure));
    }
  }

  // ...........................................................................
  /// Offers to trust the host of [repoUrl] when [stderr] shows that ssh does
  /// not know it yet: shows the key the host presents, compares it with the
  /// published fingerprint and asks. Returns true when the key was added to
  /// the known_hosts file, so the clone can be run again.
  Future<bool> _trustUnknownHost(String repoUrl, String stderr) async {
    if (!SshHostKeys.isUnknownHost(stderr) || !_hasTerminal()) {
      return false;
    }
    final host = SshHostKeys.hostOf(repoUrl);
    if (host == null) {
      return false;
    }
    return _hostTrust[host] ??= _oneDialogAtATime(
      () => _askToTrust(repoUrl, host),
    );
  }

  /// Lets the next clone of [host] offer its key again.
  void _forget(String host) => unawaited(_hostTrust.remove(host));

  /// Runs [dialog] after the dialogs started before it have ended.
  Future<bool> _oneDialogAtATime(Future<bool> Function() dialog) {
    final result = _lastDialog.then((_) => dialog());
    _lastDialog = result;
    return result;
  }

  /// Shows the key [host] presents and adds it to the known_hosts file when
  /// the user trusts it.
  ///
  /// Never throws: the offer is an extra, and whatever goes wrong in it —
  /// git not reachable, a known_hosts file that cannot be written — must
  /// not replace the error of the clone. A host that could not be scanned
  /// or stored is offered again by the next clone.
  Future<bool> _askToTrust(String repoUrl, String host) async {
    try {
      final keys = await _sshHostKeys.scan(repoUrl);
      if (keys.isEmpty) {
        _forget(host);
        return false;
      }

      final checks = [
        for (final key in keys) SshHostKeys.checkFingerprint(host, key),
      ];
      _ggLog(yellow('SSH does not know $host yet. It presents this key:'));
      for (final (i, key) in keys.indexed) {
        _ggLog('  ${key.typeName} key fingerprint: ${key.fingerprint}');
        _ggLog(switch (checks[i]) {
          FingerprintCheck.matches => green(
            '  ✓ Matches the fingerprint published for $host.',
          ),
          FingerprintCheck.differs => red(
            '  ✗ Differs from the fingerprints published for $host. Someone '
            'may intercept the connection.',
          ),
          FingerprintCheck.unknown => yellow(
            '  ! No published fingerprint is known for $host. Compare it '
            'with the one the operator of the host gives you.',
          ),
        });
      }

      // A key that differs from the published ones is never offered: a user
      // who answers yes by habit would store the key of an attacker.
      if (checks.contains(FingerprintCheck.differs)) {
        _ggLog(red('✗ The key of $host is not trusted.'));
        return false;
      }

      final trusted = await (_prompts ?? gg.GgPrompts.current).confirm(
        prompt: 'Trust $host and add it to ${_sshHostKeys.knownHostsPath}?',
        defaultValue: checks.every((c) => c == FingerprintCheck.matches),
      );
      if (!trusted) {
        return false;
      }

      _sshHostKeys.trust(keys);
      _ggLog(green('✓ Added $host to ${_sshHostKeys.knownHostsPath}.'));
      return true;
    } on Object catch (e) {
      _forget(host);
      _ggLog(red('✗ Could not add the key of $host: $e'));
      return false;
    }
  }

  /// Creates the parent folders of [directory] and returns the outermost one
  /// that had to be created, or null when they all existed already.
  Directory? _createParentDirectories(Directory directory) {
    final parent = directory.parent;
    if (parent.existsSync()) {
      return null;
    }

    // Walk up to the first existing ancestor: everything below it is new and
    // belongs to this clone alone.
    var outermost = parent;
    while (!outermost.parent.existsSync() &&
        outermost.parent.path != outermost.path) {
      outermost = outermost.parent;
    }

    parent.createSync(recursive: true);
    return outermost;
  }

  /// Removes what a failed clone left behind: the target folder when git
  /// created but did not fill it, and the folders [_createParentDirectories]
  /// made for it.
  ///
  /// Only the target folder is searched. Its parents are deleted one by one
  /// while they are empty and never searched: clones run in parallel, and a
  /// parent can hold the folder of another clone git is filling right now.
  void _removeLeftovers({
    required Directory target,
    required Directory? createdRoot,
  }) {
    _deleteEmptyTree(target);
    if (createdRoot == null) {
      return;
    }
    var directory = target.parent;
    while (_deleteIfEmpty(directory) && directory.path != createdRoot.path) {
      directory = directory.parent;
    }
  }

  /// Deletes [directory] when it holds nothing but empty folders — so a tree
  /// of empty folders vanishes bottom up.
  ///
  /// git removes what a failed clone created by itself. On Windows such a
  /// folder can still show up in a listing and be gone, or still locked,
  /// a moment later. A folder that cannot be listed or deleted is left as
  /// it is: a leftover must never hide the error of the clone.
  void _deleteEmptyTree(Directory directory) {
    try {
      if (!directory.existsSync()) {
        return;
      }
      for (final entry in directory.listSync()) {
        if (entry is Directory) {
          _deleteEmptyTree(entry);
        }
      }
    } on FileSystemException {
      return;
    }
    _deleteIfEmpty(directory);
  }

  /// Deletes [directory] when it is empty and returns whether it is gone.
  /// The operating system refuses to delete a folder that is not empty.
  bool _deleteIfEmpty(Directory directory) {
    try {
      directory.deleteSync();
      return true;
    } on FileSystemException {
      return !directory.existsSync();
    }
  }

  /// Returns true when [repoUrl] points at a git repository the caller can
  /// reach. Used to find out which organizations own a repository of a given
  /// name without cloning any of them.
  ///
  /// `ls-remote` is asked without `--exit-code`, so a repository that exists
  /// but is still empty counts as present too.
  Future<bool> remoteExists(String repoUrl) async {
    try {
      final result = await _gitRetry.run(
        () => processRunner('git', <String>['ls-remote', repoUrl]),
        ggLog: _ggLog,
        description: 'git ls-remote $repoUrl',
      );
      return result.exitCode == 0;
    } catch (_) {
      // A missing git binary must not look like a missing repository.
      return false;
    }
  }

  /// Checks out a new branch [branchName] in the repository at [repoPath].
  /// Throws an exception if the checkout fails.
  Future<void> checkoutBranch(String branchName, String repoPath) async {
    final result = await processRunner('git', <String>[
      '-C',
      repoPath,
      'checkout',
      '-b',
      branchName,
    ]);
    if (result.exitCode != 0) {
      throw Exception(
        cError(
          'Failed to checkout branch $branchName in $repoPath: '
          '${result.stderr}',
        ),
      );
    }
  }
}
