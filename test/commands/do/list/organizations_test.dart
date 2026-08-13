// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_multi_core/gg_multi_core.dart';
import 'package:gg_multi_workspace/src/commands/do/list/organizations.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('ListOrganizationsCommand', () {
    late Directory tempDir;
    late Directory oceanDir;
    final messages = <String>[];

    void ggLog(String message) {
      messages.add(rmControls(message));
    }

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync('list_org_test');
      oceanDir = Directory(path.join(tempDir.path, ggMultiOceanFolder))
        ..createSync(recursive: true);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('lists organizations uniquely sorted', () async {
      final oceanPath = oceanDir.path;
      final repo1 = Directory(path.join(oceanPath, 'repo1'))..createSync();
      File(
        path.join(repo1.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: repo1\nversion: 3.0.0');
      Directory(path.join(repo1.path, '.git')).createSync();
      File(
        path.join(repo1.path, '.git', 'config'),
      ).writeAsStringSync('url = https://github.com/inlavigo/repo1.git');

      final repo2 = Directory(path.join(oceanPath, 'repo2'))..createSync();
      File(
        path.join(repo2.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: repo2\nversion: 2.5.0');
      Directory(path.join(repo2.path, '.git')).createSync();
      File(
        path.join(repo2.path, '.git', 'config'),
      ).writeAsStringSync('url = https://github.com/microsoft/repo2.git');

      final repo3 = Directory(path.join(oceanPath, 'repo3'))..createSync();
      File(
        path.join(repo3.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: repo3\nversion: 1.0.0');
      Directory(path.join(repo3.path, '.git')).createSync();
      File(
        path.join(repo3.path, '.git', 'config'),
      ).writeAsStringSync('url = https://github.com/inlavigo/repo3.git');

      final runner = CommandRunner<void>(
        'test',
        'Test ListOrganizationsCommand',
      );
      runner.addCommand(
        ListOrganizationsCommand(ggLog: ggLog, workspacePath: oceanPath),
      );
      await runner.run(['orgs']);

      expect(
        messages,
        contains('inlavigo -- https://github.com/orgs/inlavigo/'),
      );
      expect(
        messages,
        contains('microsoft -- https://github.com/orgs/microsoft/'),
      );
    });

    test('handles unknown organization from invalid git config', () async {
      final oceanPath = oceanDir.path;
      final repo = Directory(path.join(oceanPath, 'repo_unknown'))
        ..createSync();
      File(
        path.join(repo.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: repo_unknown\nversion: 1.0.0');
      Directory(path.join(repo.path, '.git')).createSync();
      File(
        path.join(repo.path, '.git', 'config'),
      ).writeAsStringSync('invalid config content');

      final runner = CommandRunner<void>(
        'test',
        'Test ListOrganizationsCommand',
      );
      runner.addCommand(
        ListOrganizationsCommand(ggLog: ggLog, workspacePath: oceanPath),
      );
      await runner.run(['orgs']);

      // The repository organization should be 'unknown'
      expect(messages, contains('unknown'));
    });

    test('should print "No organizations found." '
        'if ocean is empty', () async {
      final runner = CommandRunner<void>(
        'test',
        'Test ListOrganizationsCommand',
      );
      runner.addCommand(
        ListOrganizationsCommand(ggLog: ggLog, workspacePath: oceanDir.path),
      );
      await runner.run(['orgs']);
      expect(messages, contains('No organizations found.'));
    });

    test('prints help message when --help is passed', () async {
      final runner = CommandRunner<void>(
        'test',
        'ListOrganizationsCommand Help',
      );
      runner.addCommand(
        ListOrganizationsCommand(ggLog: (_) {}, workspacePath: oceanDir.path),
      );
      final output = await capturePrint(
        code: () async {
          await runner.run(['orgs', '--help']);
        },
      );
      expect(output.first, contains('List all organizations of the ocean'));
    });
  });
}
