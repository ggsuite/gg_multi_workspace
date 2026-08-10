// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_multi_core/gg_multi_core.dart';
import 'package:gg_one/gg_one.dart' as gg;
import 'package:path/path.dart' as path;
import 'package:pubspec_parse/pubspec_parse.dart';

import 'package:gg_multi_workspace/src/backend/git_handler.dart';

/// Lets the user pick the organization a repository named [repoName] should
/// be taken from. Returns null when the selection was cancelled.
typedef SelectOrganization =
    Future<Organization?> Function(
      String repoName,
      List<Organization> organizations,
    );

/// Returns the clone url of [repoName] within [org].
String repoUrlOfOrganization(Organization org, String repoName) {
  final baseUrl = org.url.endsWith('/') ? org.url : '${org.url}/';
  return '$baseUrl$repoName.git';
}

/// Asks the user which organization a repository should be taken from.
// coverage:ignore-start
Future<Organization?> defaultSelectOrganization(
  String repoName,
  List<Organization> organizations,
) async {
  gg.throwWhenNotATerminal(
    'the organization prompt',
    'pass the full repository url instead of the plain name "$repoName"',
  );
  final index = gg.GgPrompts.current.select(
    prompt: '$repoName exists in several organizations. Which one?',
    options: <String>[for (final org in organizations) '${org.name}/$repoName'],
  );
  return organizations[index];
}
// coverage:ignore-end

/// Helper function to add a repository given a target argument.
/// It supports various formats like URLs, SSH links, and plain names.
/// For organization URLs, it fetches all repositories and clones them.
///
/// The [force] parameter determines whether an existing cloned
/// repository should be overwritten. If false and the destination
/// already exists and is not empty, the function reports it as already added.
///
/// The [logIfAlreadyAdded] parameter controls whether the "already added"
/// message is logged when a repository is skipped because it's already
/// present. This can be disabled when adding to a ticket workspace to
/// suppress duplicate logs.
///
/// The optional [onRepoAdded] callback is executed for every repository that is
/// ensured to be present (either cloned or detected as already cloned).  This
/// makes it easy to plug-in additional behaviour (e.g. copy the repo to a
/// ticket workspace) without touching the core cloning logic.
///
/// A plain repository name can exist in more than one of the known
/// organizations. Every organization is asked whether it owns it, and when
/// several do, [selectOrganization] lets the user pick one.
Future<void> addRepositoryHelper({
  required String targetArg,
  required GgLog ggLog,
  required GitHandler gitCloner,
  GitHubPlatform? gitHubPlatform,
  AzureDevOpsPlatform? azureDevOpsPlatform,
  required String workspacePath,
  bool force = false,
  bool logIfAlreadyAdded = true,
  Future<void> Function(String repoName)? onRepoAdded,
  SelectOrganization? selectOrganization,
}) async {
  // coverage:ignore-start
  gitHubPlatform ??= GitHubPlatform();
  azureDevOpsPlatform ??= AzureDevOpsPlatform();
  selectOrganization ??= defaultSelectOrganization;
  // coverage:ignore-end
  // ---------------------------------------------------------------------------
  /// Attempts to clone [repoUrl] as [repoName] into the organization folder
  /// of [workspacePath] the URL points at (`<workspace>/<org>/<repo>`).
  /// If [allowFallback] is true and cloning fails, tries each known
  /// organization from .organizations file as a fallback.
  Future<void> attemptClone(
    String repoUrl,
    String repoName, {
    bool allowFallback = false,
  }) async {
    // The repository is looked up in the whole workspace, so one that still
    // sits directly in it is not cloned a second time into its org folder.
    final existing = RepoFolderResolver.resolve(
      workspacePath: workspacePath,
      repoName: repoName,
    );

    // If repository folder already exists and is not empty ....................
    if (existing != null && existing.listSync().isNotEmpty) {
      if (!force) {
        if (logIfAlreadyAdded) {
          ggLog(darkGray('✓ $repoName (already added).'));
        }
        if (onRepoAdded != null) {
          await onRepoAdded(repoName);
        }
        return;
      } else {
        await existing.delete(recursive: true);
        RepoFolderResolver.removeEmptyOrgFolder(
          workspacePath: workspacePath,
          repoDir: existing,
        );
      }
    }

    final destination = RepoFolderResolver.destination(
      workspacePath: workspacePath,
      repoUrl: repoUrl,
      repoName: repoName,
    );

    // Try to clone the repository ............................................
    try {
      await gitCloner.cloneRepo(repoUrl, destination);
      ggLog(darkGray('✓ $repoName from $repoUrl'));
      try {
        OrganizationUtils.appendOrganization(workspacePath, repoUrl);
      } catch (_) {
        // Swallow errors: organization info shouldn't block the core flow
      }
      if (onRepoAdded != null) {
        await onRepoAdded(repoName);
      }
      return;
    } catch (e) {
      if (!allowFallback) {
        rethrow;
      }
      // Attempt fallback: try each known organization from .organizations
      final orgs = OrganizationUtils.readOrganizations(workspacePath);
      bool anySuccess = false;
      for (final org in orgs) {
        final fallbackUrl = repoUrlOfOrganization(org, repoName);
        try {
          // The fallback URL names another organization than the one guessed
          // from the target, so the destination is recomputed from it.
          await gitCloner.cloneRepo(
            fallbackUrl,
            RepoFolderResolver.destination(
              workspacePath: workspacePath,
              repoUrl: fallbackUrl,
              repoName: repoName,
            ),
          );
          ggLog(darkGray('✓ $repoName from $fallbackUrl'));
          try {
            OrganizationUtils.appendOrganization(workspacePath, fallbackUrl);
          } catch (_) {}
          if (onRepoAdded != null) {
            await onRepoAdded(repoName);
          }
          anySuccess = true;
          break;
        } catch (_) {
          // Continue trying next
        }
      }
      if (!anySuccess) {
        // A repository nobody owns is a typo in the name much more often than
        // it is a broken remote, so the run stops here instead of continuing
        // with a repository that will be missing from every following step.
        ggLog(
          cError(
            'Failed to clone repository '
            '$repoName from any known organizations.',
          ),
        );
        throw Exception(
          cError(
            'Repository "$repoName" was not found. Check the name, or pass '
            'the full repository url.',
          ),
        );
      }
      return;
    }
  }

  // ---------------------------------------------------------------------------
  // Normalize URL: remove trailing "#" and "/" so that
  // "https://github.com/ggsuite/" and "https://github.com/ggsuite" behave the
  // same. This must happen before any URI parsing logic.
  var cleanedUrl = targetArg;
  while (cleanedUrl.endsWith('#') || cleanedUrl.endsWith('/')) {
    cleanedUrl = cleanedUrl.substring(0, cleanedUrl.length - 1);
  }

  final parsedUri = Uri.tryParse(cleanedUrl);

  if (parsedUri != null &&
      (parsedUri.scheme == 'http' || parsedUri.scheme == 'https') &&
      parsedUri.host.isNotEmpty) {
    UrlParser urlParser = const UrlParser();
    final parsedUrl = urlParser.parse(cleanedUrl);

    final uri = parsedUri;
    if (uri.pathSegments.isEmpty ||
        uri.pathSegments.every((segment) => segment.trim().isEmpty)) {
      throw Exception(cError('Invalid organization URL provided: $cleanedUrl'));
    }
    if (parsedUrl.repo == null &&
        parsedUrl.org != null &&
        parsedUrl.platformType == 'github') {
      // Treat as organization URL ---------------------------------------------
      try {
        final List<Repository> repos = await gitHubPlatform.fetchOrgRepos(
          parsedUrl.org!,
        );
        if (repos.isEmpty) {
          ggLog(
            cWarn(
              'No repositories found for organization '
              '${parsedUrl.org!}',
            ),
          );
          return;
        }
        ggLog(darkGray('Cloning repos ...'));
        await runWithLimit(
          repos,
          4,
          (repo) => attemptClone(repo.cloneUrl, repo.name),
        );
      } catch (e) {
        // A missing/unauthenticated GitHub CLI surfaces as a friendly hint;
        // print it cleanly and stop instead of aborting with a stack trace
        // (mirrors the Azure branch below).
        if (e.toString().contains('Bitte installiere die GitHub CLI')) {
          ggLog(cWarn(e.toString().replaceAll('Exception: ', '')));
          return;
        } else {
          rethrow;
        }
      }
    } else if (parsedUrl.repo == null &&
        parsedUrl.org != null &&
        parsedUrl.platformType == 'azure' &&
        parsedUrl.project != null) {
      // Treat as Azure organization URL ---------------------------------------
      try {
        final List<Repository> repos = await azureDevOpsPlatform.fetchOrgRepos(
          parsedUrl.org!,
          project: parsedUrl.project,
        );
        if (repos.isEmpty) {
          ggLog(
            cWarn(
              'No repositories found for organization '
              '${parsedUrl.org!} and project ${parsedUrl.project}',
            ),
          );
          return;
        }
        ggLog(darkGray('Cloning repos ...'));
        await runWithLimit(
          repos,
          4,
          (repo) => attemptClone(repo.cloneUrl, repo.name),
        );
      } catch (e) {
        if (e.toString().contains('Bitte installiere die Azure CLI')) {
          ggLog(cWarn(e.toString().replaceAll('Exception: ', '')));
          return;
        } else {
          rethrow;
        }
      }
    } else {
      // Treat as a repository URL ---------------------------------------------
      String repoUrl = cleanedUrl;
      // `github.com/orgs/<org>/<repo>` names the repository, but it is a web
      // path, not a clone url — git cannot fetch from it. Rebuild the plain
      // `github.com/<org>/<repo>` form the platform actually serves.
      if (parsedUrl.platformType == 'github' &&
          parsedUrl.org != null &&
          parsedUrl.repo != null &&
          uri.pathSegments.isNotEmpty &&
          uri.pathSegments.first == 'orgs') {
        repoUrl =
            '${uri.scheme}://${uri.host}/'
            '${parsedUrl.org}/${parsedUrl.repo}';
      }
      if (!repoUrl.endsWith('.git')) {
        repoUrl = '$repoUrl.git';
      }
      final String repoName = extractRepoName(repoUrl) ?? 'unknown_repo';
      await attemptClone(repoUrl, repoName);
    }
  } else if (targetArg.startsWith('git@ssh.dev.azure.com:')) {
    // Azure DevOps SSH --------------------------------------------------------
    final String repoName = extractRepoName(targetArg) ?? 'unknown_repo';
    await attemptClone(targetArg, repoName);
  } else if (targetArg.startsWith('git@')) {
    // SSH URL -----------------------------------------------------------------
    final String repoName = extractRepoName(targetArg) ?? 'unknown_repo';
    await attemptClone(targetArg, repoName);
  } else if (targetArg.contains('/')) {
    // username/repo -----------------------------------------------------------
    final String repoUrl = 'https://github.com/$targetArg.git';
    final String repoName = extractRepoName(repoUrl) ?? 'unknown_repo';
    await attemptClone(repoUrl, repoName);
  } else {
    // plain repo name ---------------------------------------------------------
    // The name alone does not say which organization is meant, so every known
    // one is asked whether it owns a repository of that name. A repo that is
    // already in the workspace is left to attemptClone, which reports it —
    // no remote is asked and nothing is prompted for.
    final present = RepoFolderResolver.resolve(
      workspacePath: workspacePath,
      repoName: targetArg,
    );
    final alreadyAdded =
        !force && present != null && present.listSync().isNotEmpty;

    final owners = alreadyAdded
        ? const <Organization>[]
        : await organizationsOwningRepo(
            repoName: targetArg,
            workspacePath: workspacePath,
            gitCloner: gitCloner,
          );

    if (owners.length > 1) {
      final chosen = await selectOrganization(targetArg, owners);
      if (chosen == null) {
        ggLog(cWarn('No organization chosen for $targetArg.'));
        return;
      }
      await attemptClone(repoUrlOfOrganization(chosen, targetArg), targetArg);
      return;
    }

    if (owners.length == 1) {
      await attemptClone(
        repoUrlOfOrganization(owners.first, targetArg),
        targetArg,
      );
      return;
    }

    // No known organization owns it: guess `github.com/<name>/<name>` and
    // fall back to trying the known organizations in turn.
    final String repoUrl = 'https://github.com/$targetArg/$targetArg.git';
    final String repoName = extractRepoName(repoUrl) ?? 'unknown_repo';
    await attemptClone(repoUrl, repoName, allowFallback: true);
  }
}

/// Returns the known organizations of [workspacePath] that own a repository
/// named [repoName], in the order they are registered.
///
/// Returns an empty list when fewer than two organizations are known — then
/// there is nothing to choose and the caller's cheaper fallback path does the
/// job without asking a remote.
Future<List<Organization>> organizationsOwningRepo({
  required String repoName,
  required String workspacePath,
  required GitHandler gitCloner,
}) async {
  final orgs = OrganizationUtils.readOrganizations(workspacePath);
  if (orgs.length < 2) {
    return const <Organization>[];
  }

  // The remotes are asked in parallel, but the result keeps the order of the
  // organizations so the selection is stable across runs.
  final owns = List<bool>.filled(orgs.length, false);
  await runWithLimit(List<int>.generate(orgs.length, (i) => i), 4, (
    index,
  ) async {
    owns[index] = await gitCloner.remoteExists(
      repoUrlOfOrganization(orgs[index], repoName),
    );
  });

  return <Organization>[
    for (var i = 0; i < orgs.length; i++)
      if (owns[i]) orgs[i],
  ];
}

/// Processes [items] with [task], running up to [maxParallel] tasks at a time.
/// Tasks run in submission order; the first failure is rethrown after all
/// already-started tasks have settled.
Future<void> runWithLimit<T>(
  Iterable<T> items,
  int maxParallel,
  Future<void> Function(T item) task,
) async {
  final queue = items.toList();
  var nextIndex = 0;

  Future<void> worker() async {
    while (true) {
      if (nextIndex >= queue.length) {
        return;
      }
      final item = queue[nextIndex++];
      await task(item);
    }
  }

  final workers = <Future<void>>[
    for (var i = 0; i < maxParallel && i < queue.length; i++) worker(),
  ];

  await Future.wait(workers);
}

/// Extracts the repository name from a git URL supporting:
/// - GitHub SSH (git@github.com:owner/repo.git)
/// - Azure DevOps SSH (git@ssh.dev.azure.com:v3/org/project/repo(.git))
/// - HTTPS (https://github.com/owner/repo(.git))
/// - username/repo
String? extractRepoName(String repoUrl) {
  UrlParser urlParser = const UrlParser();
  return urlParser.parse(repoUrl).repo;
}

/// Retrieves the Pubspec for a repository in the ocean.
/// Returns null if pubspec.yaml is not found or parsing fails.
Pubspec? getPubspecFromWorkspace({
  required String targetArg,
  required String workspacePath,
  required GgLog ggLog,
}) {
  final repoName = extractRepoName(targetArg);
  // Resolve by exact folder name, then manifest package name, so a
  // cross-language bridge repo (folder name != package name) is found too.
  final repoDir =
      (repoName != null
          ? RepoFolderResolver.resolve(
              workspacePath: workspacePath,
              repoName: repoName,
            )
          : null) ??
      Directory(path.join(workspacePath, repoName ?? ''));
  final pubspecPath = path.join(repoDir.path, 'pubspec.yaml');
  final pubspecFile = File(pubspecPath);
  if (!pubspecFile.existsSync()) {
    ggLog(
      cError(
        'pubspec.yaml not found in '
        'project $repoName in workspace $workspacePath.',
      ),
    );
    return null;
  }
  try {
    final content = pubspecFile.readAsStringSync();
    return Pubspec.parse(content);
  } catch (e) {
    ggLog(cError('Error parsing pubspec.yaml: $e'));
    return null;
  }
}
