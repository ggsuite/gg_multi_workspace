// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';

import 'package:gg_multi_core/gg_multi_core.dart';

/// A class holding repository information.
class RepoInfo {
  /// Constructor
  RepoInfo({
    required this.name,
    required this.version,
    required this.language,
    required this.organization,
  });

  /// Repository name.
  final String name;

  /// Repository version string.
  final String version;

  /// Programming language of the repository.
  final String language;

  /// Organization extracted from the git URL.
  final String organization;
}

/// Returns repository information for the repository at [repoPath].
Future<RepoInfo> getRepoInfo(String repoPath) async {
  final name = p.basename(repoPath);
  String version = 'v.1.0.0';
  final pubspecFile = File(p.join(repoPath, 'pubspec.yaml'));
  if (await pubspecFile.exists()) {
    try {
      final content = await pubspecFile.readAsString();
      final pubspec = Pubspec.parse(content);
      if (pubspec.version != null) {
        version = 'v.${pubspec.version.toString()}';
      }
    } catch (e) {
      // Use default version.
    }
  }
  // Determine language.
  String language;
  final packageJson = File(p.join(repoPath, 'package.json'));
  final hasPubspec = await pubspecFile.exists();
  final hasPackageJson = await packageJson.exists();
  if (hasPubspec && hasPackageJson) {
    // Cross-language bridge: a repo carrying both a Dart and a Node manifest.
    language = 'dart+nodejs';
  } else if (hasPubspec) {
    language = 'dart';
  } else if (hasPackageJson) {
    language = 'nodejs';
  } else {
    final dir = Directory(repoPath);
    final files = dir.listSync(recursive: true).whereType<File>().toList();
    if (files.any((f) => f.path.endsWith('.py'))) {
      language = 'python';
    } else if (files.any((f) => f.path.endsWith('.java'))) {
      language = 'Java';
    } else if (files.any((f) => f.path.endsWith('.cpp'))) {
      language = 'c++';
    } else {
      language = 'dart';
    }
  }
  String organization = 'unknown';
  final gitConfig = File(p.join(repoPath, '.git', 'config'));
  if (await gitConfig.exists()) {
    try {
      final lines = await gitConfig.readAsLines();
      final urlLine = lines.firstWhere(
        (line) => line.trim().startsWith('url ='),
        orElse: () => '',
      );
      if (urlLine.isNotEmpty) {
        final parts = urlLine.split('=');
        if (parts.length >= 2) {
          final url = parts[1].trim();
          if (url.startsWith('git@')) {
            final match = RegExp(r'git@[^:]+:([^/]+)/').firstMatch(url);
            if (match != null) {
              organization = match.group(1)!;
            }
          } else {
            try {
              final uri = Uri.parse(url);
              if (uri.pathSegments.length >= 2) {
                organization = uri.pathSegments.first;
              }
            } catch (e) {
              // ignore
            }
          }
        }
      }
    } catch (e) {
      // ignore errors
    }
  }
  return RepoInfo(
    name: name,
    version: version,
    language: language,
    organization: organization,
  );
}

/// Returns list of repository information for repos in [oceanWorkspacePath].
///
/// The repositories inside the organization folders are covered as well as
/// the ones that still sit directly in the workspace.
Future<List<RepoInfo>> getAllRepoInfos(String oceanWorkspacePath) async {
  final infos = <RepoInfo>[];
  for (final d in RepoFolderResolver.repoDirs(oceanWorkspacePath)) {
    infos.add(await getRepoInfo(d.path));
  }
  return infos;
}
