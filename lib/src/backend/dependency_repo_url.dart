// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_one/gg_one.dart' as gg;
import 'package:http/http.dart' as http;

/// Fetches the repository URL for a dependency from its registry: pub.dev for
/// Dart/Flutter, the npm registry for TypeScript. Returns the URL if found,
/// otherwise null.
Future<String?> fetchDependencyRepoUrl(
  String packageName, {
  gg.ProjectType type = gg.ProjectType.dart,
  Future<http.Response> Function(Uri)? packageFetcher,
}) async {
  final fetcher = packageFetcher ?? http.get;

  if (type == gg.ProjectType.typescript) {
    return _fetchNpmRepoUrl(packageName, fetcher);
  }

  final url = Uri.parse('https://pub.dev/api/packages/$packageName');
  final response = await fetcher(url);
  if (response.statusCode != 200) {
    throw Exception(
      cError('Failed to fetch package info from pub.dev for $packageName'),
    );
  }
  final data = jsonDecode(response.body) as Map<String, dynamic>;
  if (data.containsKey('latest')) {
    final latest = data['latest'] as Map<String, dynamic>;
    if (latest.containsKey('pubspec')) {
      final pubspec = latest['pubspec'] as Map<String, dynamic>;
      if (pubspec.containsKey('repository')) {
        final repoUrl = pubspec['repository'] as String;
        return repoUrl;
      }
    }
  }
  return null;
}

/// Fetches a dependency's repository URL from the npm registry.
Future<String?> _fetchNpmRepoUrl(
  String packageName,
  Future<http.Response> Function(Uri) fetcher,
) async {
  final url = Uri.parse('https://registry.npmjs.org/$packageName');
  final response = await fetcher(url);
  if (response.statusCode != 200) {
    throw Exception(
      cError('Failed to fetch package info from npm for $packageName'),
    );
  }
  final data = jsonDecode(response.body) as Map<String, dynamic>;
  final repository = data['repository'];

  String? raw;
  if (repository is String) {
    raw = repository;
  } else if (repository is Map<String, dynamic>) {
    raw = repository['url']?.toString();
  }
  if (raw == null) {
    return null;
  }
  // npm repository URLs are commonly of the form
  // "git+https://github.com/owner/repo.git".
  return raw.replaceFirst(RegExp(r'^git\+'), '');
}
