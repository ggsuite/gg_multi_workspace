// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;

import 'package:gg_multi_workspace/src/backend/add_repository_helper.dart';
import 'package:gg_multi_core/gg_multi_core.dart';

/// Command to list dependencies of a project from the ocean.
class ListDepsCommand extends Command<dynamic> {
  /// Constructor
  ListDepsCommand({
    required this.ggLog,
    String? workspacePath,
    // coverage:ignore-start
  }) : workspacePath =
           workspacePath ?? WorkspaceUtils.defaultOceanWorkspacePath() {
    _addArgs();
  }
  // coverage:ignore-end

  /// Log function.
  final GgLog ggLog;

  /// Workspace path for projects.
  final String workspacePath;

  @override
  String get name => 'deps';

  @override
  String get description => 'List the dependencies of an ocean repo';

  void _addArgs() {
    argParser.addOption(
      'depth',
      abbr: 'd',
      help: 'The depth for listing dependencies.',
      defaultsTo: '1',
    );
  }

  @override
  void run() {
    if (argResults!.rest.isEmpty) {
      throw UsageException('Missing target repository parameter.', usage);
    }
    final targetArg = argResults!.rest[0];
    final pubspec = getPubspecFromWorkspace(
      targetArg: targetArg,
      workspacePath: workspacePath,
      ggLog: ggLog,
    );
    if (pubspec == null) {
      return;
    }
    final projectLine =
        '${pubspec.name} v.${pubspec.version?.toString() ?? '1.0.0'} (dart)';
    ggLog(projectLine);
    pubspec.dependencies.forEach((key, value) {
      ggLog(' |-- $key ${value.toString()} (dart)');
    });
    pubspec.devDependencies.forEach((key, value) {
      ggLog(' |-- dev:$key ${value.toString()} (dart)');
    });

    // A cross-language bridge ships a package.json alongside its pubspec.yaml;
    // list its TypeScript dependencies too.
    // coverage:ignore-start
    final repoName = extractRepoName(targetArg) ?? targetArg;
    final repoDir =
        RepoFolderResolver.resolve(
          workspacePath: workspacePath,
          repoName: repoName,
        ) ??
        Directory(path.join(workspacePath, repoName));
    // coverage:ignore-end
    final packageJson = File(path.join(repoDir.path, 'package.json'));
    if (packageJson.existsSync()) {
      _listPackageJsonDeps(packageJson);
    }
  }

  void _listPackageJsonDeps(File packageJson) {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(packageJson.readAsStringSync()) as Map<String, dynamic>;
    } catch (e) {
      ggLog('Error parsing package.json: $e');
      return;
    }

    void listSection(String key, String prefix) {
      final section = json[key];
      if (section is Map) {
        section.forEach((depName, spec) {
          ggLog(' |-- $prefix$depName ${spec.toString()} (typescript)');
        });
      }
    }

    listSection('dependencies', '');
    listSection('devDependencies', 'dev:');
  }
}
