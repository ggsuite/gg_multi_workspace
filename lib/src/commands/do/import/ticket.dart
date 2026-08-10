// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_git/gg_git.dart';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_git/gg_git.dart' as gg_git;
import 'package:gg_log/gg_log.dart';
import 'package:gg_process/gg_process.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import 'package:gg_multi_core/gg_multi_core.dart';
import 'package:gg_one/gg_one.dart'
    show GgPrompts, throwWhenNotATerminal;
import 'package:gg_multi_workspace/src/backend/git_handler.dart';
import 'package:gg_multi_workspace/src/backend/repo_setup.dart';

/// Lets the user pick one branch from [branches]; returns null on cancel.
typedef BranchSelector = Future<String?> Function(List<String> branches);

/// Copies a directory tree; injectable for tests.
typedef CopyDirectory = Future<void> Function(Directory src, Directory dest);

/// Downloads the `ticket.json` at [url]; injectable for tests.
typedef TicketJsonFetcher = Future<String> Function(Uri url);

/// Reproduces a whole ticket from a `ticket.json`.
///
/// `gg multi do checkout <X>` resolves [X] in this order:
/// * [X] is an `http(s)` URL → the `ticket.json` is downloaded from there;
/// * [X] is a file → the `ticket.json` is read from it; a directory is taken as
///   a ticket folder and its `ticket.json` is read;
/// * *(legacy)* [X] names a `.master` repo, or a ticket branch — the marker
///   older gg versions committed to `.gg/` is read from `origin/<branch>`.
///
/// Since a `ticket.json` no longer travels with the feature branch, sharing a
/// ticket is explicit: hand over the file or a URL pointing to it.
///
/// The `ticket.json` is used to recreate the ticket workspace, clone any
/// missing repositories, and check out the existing feature branch in every
/// repository (with its already path-localized deps), so a ticket created
/// elsewhere is reproduced. Unlike a fresh `do add` it does not re-install git
/// hooks or `.gitattributes`.
/// The `ticket.json` is taken from a file path or an http(s) URL. The command
/// recreates the ticket folder, clones the missing repos, checks out their
/// feature branch and installs the dependencies.
class DoCheckoutCommand extends Command<dynamic> {
  /// Constructor.
  DoCheckoutCommand({
    required this.ggLog,
    GitHandler? gitHandler,
    gg_git.Fetch? fetch,
    gg_git.Checkout? checkout,
    gg_git.ShowFile? showFile,
    gg_git.RemoteBranches? remoteBranches,
    gg_git.RemoteBranchExists? remoteBranchExists,
    String? oceanWorkspacePath,
    String? executionPath,
    ProcessRunner? processRunner,
    BranchSelector? selectBranch,
    CopyDirectory? copyDir,
    TicketJsonFetcher? fetchTicketJson,
    // coverage:ignore-start
  }) : gitHandler = gitHandler ?? GitHandler(),
       _fetch = fetch ?? gg_git.Fetch(ggLog: ggLog),
       _checkout = checkout ?? gg_git.Checkout(ggLog: ggLog),
       _showFile = showFile ?? gg_git.ShowFile(ggLog: ggLog),
       _remoteBranches = remoteBranches ?? gg_git.RemoteBranches(ggLog: ggLog),
       _remoteBranchExists =
           remoteBranchExists ?? gg_git.RemoteBranchExists(ggLog: ggLog),
       oceanWorkspacePath =
           oceanWorkspacePath ?? WorkspaceUtils.defaultOceanWorkspacePath(),
       executionPath = executionPath ?? Directory.current.path,
       processRunner = processRunner ?? ggRunProcess,
       _selectBranch = selectBranch ?? _defaultSelectBranch,
       _copyDir = copyDir ?? copyDirectory,
       _fetchTicketJson = fetchTicketJson ?? _defaultFetchTicketJson;
  // coverage:ignore-end

  /// The log function.
  final GgLog ggLog;

  /// Clones repositories that are missing from the ocean.
  final GitHandler gitHandler;

  final gg_git.Fetch _fetch;
  final gg_git.Checkout _checkout;
  final gg_git.ShowFile _showFile;
  final gg_git.RemoteBranches _remoteBranches;
  final gg_git.RemoteBranchExists _remoteBranchExists;

  /// Resolved ocean path.
  final String oceanWorkspacePath;

  /// The path from which the command was executed.
  final String executionPath;

  /// Runs `dart pub get` / `<pm> install` after checkout.
  final ProcessRunner processRunner;

  final BranchSelector _selectBranch;
  final CopyDirectory _copyDir;
  final TicketJsonFetcher _fetchTicketJson;

  @override
  String get name => 'ticket';

  @override
  String get description => 'Reproduce a ticket from a ticket.json path or URL';

  @override
  String get invocation => 'gg multi do checkout <path|url>';

  // coverage:ignore-start
  static Future<String?> _defaultSelectBranch(List<String> branches) async {
    throwWhenNotATerminal(
      'the ticket branch prompt',
      'pass the branch explicitly instead of a bare repository name',
    );
    final index = await GgPrompts.current.select(
      prompt: 'Select a ticket branch',
      options: branches,
    );
    return branches[index];
  }

  static Future<String> _defaultFetchTicketJson(Uri url) async {
    final response = await http.get(url);
    if (response.statusCode != 200) {
      throw Exception(
        cError(
          'Could not download ticket.json from "$url": '
          'HTTP ${response.statusCode}.',
        ),
      );
    }
    return response.body;
  }
  // coverage:ignore-end

  @override
  Future<void> run() async {
    if (argResults!.rest.isEmpty) {
      throw UsageException('Missing path or URL of a ticket.json.', usage);
    }
    final arg = argResults!.rest.first;

    // Maintenance: move the repositories of an old ocean into
    // their organization folders before resolving anything.
    migrateToOrgFolders(workspacePath: oceanWorkspacePath, ggLog: ggLog);

    // Mode URL: arg points to a downloadable ticket.json.
    final url = _ticketJsonUrl(arg);
    if (url != null) {
      ggLog(cDetail('Downloading ticket.json from $url'));
      final content = await _fetchTicketJson(url);
      await _reproduce(_parseTicket(content, url.toString()));
      return;
    }

    // Mode file: arg is a ticket.json, or a ticket folder containing one.
    final file = _ticketJsonFile(arg);
    if (file != null) {
      await _reproduce(_parseTicket(file.readAsStringSync(), file.path));
      return;
    }

    // Mode 1: executed inside an ocean repo → arg is the ticket name.
    final currentRepo = _currentOceanRepoPath();
    if (currentRepo != null) {
      await _reproduceFromBranch(
        repoPath: currentRepo,
        branch: arg,
        alreadyFetched: false,
      );
      return;
    }

    // Mode 2: arg is a known ocean repo → interactive branch selection.
    final repoDir = RepoFolderResolver.resolve(
      workspacePath: oceanWorkspacePath,
      repoName: arg,
    );
    if (repoDir != null) {
      await _handleRepoMode(repoDir);
      return;
    }

    // Mode 3: arg is a ticket name → search all ocean repos for the branch.
    for (final repo in _listOceanRepos()) {
      try {
        await _fetch.get(directory: repo, ggLog: ggLog);
      } catch (e) {
        ggLog(cError('Failed to fetch ${path.basename(repo.path)}: $e'));
        continue;
      }
      final exists = await _remoteBranchExists.get(
        directory: repo,
        ggLog: ggLog,
        branch: arg,
      );
      if (exists) {
        await _reproduceFromBranch(
          repoPath: repo.path,
          branch: arg,
          alreadyFetched: true,
        );
        return;
      }
    }

    throw Exception(
      cError(
        '"$arg" is neither a ticket.json path, an http(s) URL, a repository of '
        'the ocean, nor a branch of one of its repositories.',
      ),
    );
  }

  // ...........................................................................
  /// Returns [arg] as an http(s) URL, or null when it is not one.
  static Uri? _ticketJsonUrl(String arg) {
    final uri = Uri.tryParse(arg);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    return uri;
  }

  // ...........................................................................
  /// Returns the `ticket.json` [arg] denotes — the file itself, or the
  /// `ticket.json` of the ticket folder [arg] points to — or null when [arg]
  /// is no path at all and the legacy branch modes should have a go.
  ///
  /// An [arg] that *is* a path is never handed on to those modes: a folder
  /// without a `ticket.json` is a mistake worth naming, not a repository name
  /// that happens to look like a directory.
  static File? _ticketJsonFile(String arg) {
    final asFile = File(arg);
    if (asFile.existsSync()) {
      return asFile;
    }
    if (!_looksLikePath(arg) || !Directory(arg).existsSync()) {
      return null;
    }
    final inDir = File(path.join(arg, ticketJsonFileName));
    if (!inDir.existsSync()) {
      throw Exception(cError('"$arg" contains no $ticketJsonFileName.'));
    }
    return inDir;
  }

  /// Whether [arg] is meant as a path rather than as a repository or ticket
  /// name — names never carry a separator.
  static bool _looksLikePath(String arg) =>
      arg.contains(path.separator) || arg.contains('/');

  // ...........................................................................
  /// Parses [content] into a [TicketJson], naming [source] when it is invalid.
  static TicketJson _parseTicket(String content, String source) {
    try {
      return TicketJson.fromJsonString(content);
    } on FormatException catch (e) {
      throw Exception(cError('Invalid ticket.json at "$source": $e'));
    }
  }

  // ...........................................................................
  /// Fetches [repoDir], lists its remote ticket branches and lets the user pick
  /// one to reproduce.
  Future<void> _handleRepoMode(Directory repoDir) async {
    await _fetch.get(directory: repoDir, ggLog: ggLog);
    final all = await _remoteBranches.get(directory: repoDir, ggLog: ggLog);
    final branches = all.where((b) => b != 'main' && b != 'master').toList();
    if (branches.isEmpty) {
      ggLog(
        cWarn('No ticket branches found in ${path.basename(repoDir.path)}.'),
      );
      return;
    }
    final selected = await _selectBranch(branches);
    if (selected == null || selected.isEmpty) {
      return;
    }
    await _reproduceFromBranch(
      repoPath: repoDir.path,
      branch: selected,
      alreadyFetched: true,
    );
  }

  // ...........................................................................
  /// Legacy path: reads the marker older gg versions committed to `.gg/` from
  /// `origin/<branch>` of [repoPath] and reproduces the ticket it describes.
  ///
  /// gg no longer writes that marker — a ticket.json stays on the machine that
  /// created it — so this only serves branches pushed by an older gg.
  Future<void> _reproduceFromBranch({
    required String repoPath,
    required String branch,
    required bool alreadyFetched,
  }) async {
    final dir = Directory(repoPath);
    if (!alreadyFetched) {
      await _fetch.get(directory: dir, ggLog: ggLog);
    }

    String? content;
    for (final markerPath in legacyTicketJsonRelativePaths) {
      content = await _showFile.get(
        directory: dir,
        ggLog: ggLog,
        ref: 'origin/$branch',
        filePath: markerPath,
      );
      if (content != null) {
        break;
      }
    }
    if (content == null) {
      throw Exception(
        cError(
          'Could not read a ticket marker from "origin/$branch" — the branch may '
          'not be pushed/fetched, or was pushed by a gg that no longer uploads '
          'one.\nCheck the ticket out from its ticket.json instead:\n'
          '  gg multi do checkout <path-or-url-of-ticket.json>',
        ),
      );
    }

    ggLog(
      cWarn(
        'Using the legacy ticket marker committed to "origin/$branch". '
        'gg does not upload it anymore — pass the path or URL of a '
        'ticket.json instead.',
      ),
    );
    await _reproduce(_parseTicket(content, 'origin/$branch'));
  }

  // ...........................................................................
  /// Recreates the ticket workspace and all its repositories on the feature
  /// branch.
  Future<void> _reproduce(TicketJson ticket) async {
    final ticketName = ticket.issueId;
    if (ticketName.isEmpty) {
      throw Exception(cError('The ticket marker has no issue_id.'));
    }

    final root = path.dirname(oceanWorkspacePath);
    final ticketDir = WorkspaceUtils.ticketDir(
      rootPath: root,
      ticketName: ticketName,
    );
    if (!ticketDir.existsSync()) {
      ticketDir.createSync(recursive: true);
    }
    // Keep the ticket.json in the reproduced workspace so it can be handed on
    // from here as well.
    writeTicketJson(ticketDir, ticket);

    final succeeded = <String>[];
    final failed = <String>[];
    for (final repo in ticket.repositories) {
      final oceanRepoDir = await _ensureOceanRepo(repo);
      if (oceanRepoDir == null) {
        ggLog(cError('Could not obtain repository ${repo.name}; skipping.'));
        failed.add(repo.name);
        continue;
      }
      final repoPath = await _setupTicketRepo(
        ticketDir: ticketDir,
        oceanRepoDir: oceanRepoDir,
        branch: ticketName,
        repoName: repo.name,
      );
      if (repoPath == null) {
        failed.add(repo.name);
      } else {
        succeeded.add(repoPath);
      }
    }

    // The workspace lists only the repos that were actually checked out.
    writeCodeWorkspaceFile(ticketDir, succeeded);

    final relPath = path.relative(ticketDir.path, from: executionPath);
    if (failed.isEmpty) {
      ggLog(cDetail('✓ Checked out ticket $ticketName'));
    } else {
      ggLog(
        cError(
          '⚠️ Checked out ticket $ticketName, but ${failed.length} repo(s) '
          'failed: ${failed.join(', ')}',
        ),
      );
    }
    ggLog(cAction('Enter the ticket workspace with:'));
    ggLog(cCmd('cd $relPath'));
  }

  // ...........................................................................
  /// Returns the ocean repository at [repo] (cloning it from its URL when it
  /// is missing), or null when it cannot be obtained.
  Future<Directory?> _ensureOceanRepo(TicketRepo repo) async {
    final existing = RepoFolderResolver.resolve(
      workspacePath: oceanWorkspacePath,
      repoName: repo.name,
    );
    if (existing != null) {
      return existing;
    }
    if (repo.url.isEmpty) {
      return null;
    }
    final target = RepoFolderResolver.destination(
      workspacePath: oceanWorkspacePath,
      repoUrl: repo.url,
      repoName: repo.name,
    );
    try {
      await gitHandler.cloneRepo(repo.url, target);
    } catch (e) {
      ggLog(cError('Failed to clone ${repo.name} from ${repo.url}: $e'));
      return null;
    }
    return Directory(target);
  }

  // ...........................................................................
  /// Copies [oceanRepoDir] into the ticket (when not already present) and
  /// checks out the existing feature [branch] there, then installs deps.
  /// Returns the path of the repo relative to the ticket root, or null when
  /// the branch could not be checked out.
  Future<String?> _setupTicketRepo({
    required Directory ticketDir,
    required Directory oceanRepoDir,
    required String branch,
    required String repoName,
  }) async {
    // The ticket holds its repos flat, independent of the organization
    // folders the ocean groups them in.
    final destDir = Directory(
      RepoFolderResolver.ticketDestination(
        ticketPath: ticketDir.path,
        repoUrl: RepoFolderResolver.remoteUrl(oceanRepoDir) ?? '',
        repoName: path.basename(oceanRepoDir.path),
      ),
    );
    final relativePath = RepoFolderResolver.relativePath(
      workspacePath: ticketDir.path,
      repoDir: destDir,
    );

    if (!(destDir.existsSync() && destDir.listSync().isNotEmpty)) {
      // Fetch the master clone so its `origin/<branch>` is available in the
      // copy, then copy it into the ticket.
      await _fetch.get(directory: oceanRepoDir, ggLog: ggLog);
      await _copyDir(oceanRepoDir, destDir);
    }

    try {
      await _checkout.get(directory: destDir, ggLog: ggLog, branch: branch);
    } catch (e) {
      ggLog(cError('Failed to checkout $branch in $repoName: $e'));
      return null;
    }

    await installRepoDependencies(
      dir: destDir,
      repoName: repoName,
      ggLog: ggLog,
      processRunner: processRunner,
    );
    ggLog(cDetail('Added $repoName on branch $branch.'));
    return relativePath;
  }

  // ...........................................................................
  /// Returns the path of the `.ocean` repository that contains
  /// [executionPath], or null when the command is not run inside one.
  ///
  /// The repository is either a direct child of the ocean or sits
  /// one level deeper inside its organization folder, so the first two
  /// segments below the workspace are checked.
  String? _currentOceanRepoPath() {
    final ocean = path.normalize(oceanWorkspacePath);
    final exec = path.normalize(executionPath);
    if (exec == ocean || !path.isWithin(ocean, exec)) {
      return null;
    }
    final segments = path.split(path.relative(exec, from: ocean));
    var repoPath = path.join(ocean, segments.first);
    if (!Directory(repoPath).existsSync()) {
      return null;
    }
    if (RepoFolderResolver.isOrgFolder(Directory(repoPath))) {
      if (segments.length < 2) {
        return null;
      }
      repoPath = path.join(repoPath, segments[1]);
      if (!Directory(repoPath).existsSync()) {
        return null;
      }
    }
    return repoPath;
  }

  // ...........................................................................
  /// Lists the git repositories of the ocean.
  List<Directory> _listOceanRepos() {
    return RepoFolderResolver.repoDirs(
      oceanWorkspacePath,
    ).where((d) => Directory(path.join(d.path, '.git')).existsSync()).toList();
  }
}
