// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_multi_workspace/src/backend/list_backend.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('list_backend', () {
    late Directory tempDir;

    setUp(() {
      // Create a temporary directory for each test
      tempDir = Directory.systemTemp.createTempSync('repo_test_');
    });

    tearDown(() {
      // Clean up temporary directory after test
      tempDir.deleteSync(recursive: true);
    });

    group('getRepoInfo', () {
      test('should return repo info with pubspec'
          ' and .git config (git@ url)', () async {
        // Create a pubspec.yaml with a valid version
        var pubspecContent = 'name: sample\nversion: 1.2.3';
        File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsStringSync(pubspecContent);

        // Create a .git/config file with a git@ URL
        Directory(p.join(tempDir.path, '.git')).createSync();
        var gitConfigContent = 'url = git@github.com:org/sample.git';
        File(
          p.join(tempDir.path, '.git', 'config'),
        ).writeAsStringSync(gitConfigContent);

        // Execute getRepoInfo
        var info = await getRepoInfo(tempDir.path);

        // Validate the returned RepoInfo
        expect(info.name, equals(p.basename(tempDir.path)));
        expect(info.version, equals('v.1.2.3'));
        expect(info.language, equals('dart'));
        expect(info.organization, equals('org'));
      });

      test('should return default version if pubspec parsing fails', () async {
        // Create a pubspec.yaml with invalid content
        File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsStringSync('bad content');

        // No .git configuration exists
        var info = await getRepoInfo(tempDir.path);

        // Expect default version as parsing fails
        expect(info.version, equals('v.1.0.0'));
        // Since pubspec.yaml exists, language defaults to dart
        expect(info.language, equals('dart'));
        expect(info.organization, equals('unknown'));
      });

      test('should return nodejs language if package.json exists', () async {
        // Create a package.json file
        File(p.join(tempDir.path, 'package.json')).writeAsStringSync('{}');

        // Execute getRepoInfo
        var info = await getRepoInfo(tempDir.path);

        // Expect language to be nodejs
        expect(info.language, equals('nodejs'));
        // Default version remains as no pubspec exists
        expect(info.version, equals('v.1.0.0'));
      });

      test(
        'should label a bridge (pubspec + package.json) as dart+nodejs',
        () async {
          File(
            p.join(tempDir.path, 'pubspec.yaml'),
          ).writeAsStringSync('name: bridge\nversion: 1.0.0');
          File(p.join(tempDir.path, 'package.json')).writeAsStringSync('{}');

          var info = await getRepoInfo(tempDir.path);

          expect(info.language, equals('dart+nodejs'));
        },
      );

      test('should return python language if a .py file exists', () async {
        // Create a dummy .py file
        File(
          p.join(tempDir.path, 'script.py'),
        ).writeAsStringSync('print("hello")');

        var info = await getRepoInfo(tempDir.path);
        expect(info.language, equals('python'));
      });

      test('should return Java language if a .java file exists', () async {
        // Create a dummy .java file
        File(
          p.join(tempDir.path, 'Main.java'),
        ).writeAsStringSync('public class Main {}');

        var info = await getRepoInfo(tempDir.path);
        expect(info.language, equals('Java'));
      });

      test('should return c++ language if a .cpp file exists', () async {
        // Create a dummy .cpp file
        File(
          p.join(tempDir.path, 'main.cpp'),
        ).writeAsStringSync('int main() { return 0; }');

        var info = await getRepoInfo(tempDir.path);
        expect(info.language, equals('c++'));
      });

      test('should return fallback dart language '
          'if no indicator exists', () async {
        // Create a dummy file with an unrelated extension
        File(
          p.join(tempDir.path, 'readme.txt'),
        ).writeAsStringSync('This is a readme file.');

        var info = await getRepoInfo(tempDir.path);
        // With no specific indicator, language should fallback to dart
        expect(info.language, equals('dart'));
      });

      test('should extract organization '
          'from .git config in http format', () async {
        // Create a pubspec.yaml to force dart language
        File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: sample');

        // Create .git/config with an HTTP URL
        Directory(p.join(tempDir.path, '.git')).createSync();
        var gitConfigContent = 'url = https://github.com/orgName/sample.git';
        File(
          p.join(tempDir.path, '.git', 'config'),
        ).writeAsStringSync(gitConfigContent);

        var info = await getRepoInfo(tempDir.path);
        expect(info.organization, equals('orgName'));
      });

      test('should set organization to unknown '
          'if .git config missing url', () async {
        // Create .git folder with a config file lacking a proper url
        Directory(p.join(tempDir.path, '.git')).createSync();
        File(
          p.join(tempDir.path, '.git', 'config'),
        ).writeAsStringSync('some other content');

        var info = await getRepoInfo(tempDir.path);
        expect(info.organization, equals('unknown'));
      });
    });

    group('getAllRepoInfos', () {
      test('should return empty list '
          'if ocean directory does not exist', () async {
        // Create and then delete a temporary
        // directory to simulate non-existence
        var nonExistingDir = Directory.systemTemp.createTempSync(
          'non_existing_',
        );
        nonExistingDir.deleteSync(recursive: true);

        var infos = await getAllRepoInfos(nonExistingDir.path);
        expect(infos, isEmpty);
      });

      test('should return list of repo infos for each subdirectory', () async {
        // Create an ocean directory inside the temporary directory
        var oceanWorkspace = Directory(p.join(tempDir.path, 'master'));
        oceanWorkspace.createSync();

        // Create Repo1: with pubspec.yaml and .git config (git@ url)
        var repo1 = Directory(p.join(oceanWorkspace.path, 'repo1'));
        repo1.createSync();
        File(
          p.join(repo1.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: repo1\nversion: 2.0.0');
        Directory(p.join(repo1.path, '.git')).createSync();
        File(
          p.join(repo1.path, '.git', 'config'),
        ).writeAsStringSync('url = git@github.com:org1/repo1.git');

        // Create Repo2: with package.json
        var repo2 = Directory(p.join(oceanWorkspace.path, 'repo2'));
        repo2.createSync();
        File(p.join(repo2.path, 'package.json')).writeAsStringSync('{}');

        // Create Repo3: with a .py file
        var repo3 = Directory(p.join(oceanWorkspace.path, 'repo3'));
        repo3.createSync();
        File(p.join(repo3.path, 'app.py')).writeAsStringSync('print("Hi")');

        // Retrieve all repository information
        var infos = await getAllRepoInfos(oceanWorkspace.path);
        expect(infos, hasLength(3));

        // Verify that repository names match subdirectory names
        var names = infos.map((repo) => repo.name).toSet();
        expect(names, containsAll(['repo1', 'repo2', 'repo3']));
      });

      test('lists the repos inside the organization folders', () async {
        // `<ocean>/<org>/<repo>` is the layout of a migrated workspace.
        final oceanWorkspace = Directory(p.join(tempDir.path, 'org_ocean'))
          ..createSync();
        final repo = Directory(p.join(oceanWorkspace.path, 'org1', 'repo1'))
          ..createSync(recursive: true);
        File(
          p.join(repo.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: repo1\nversion: 2.0.0');
        Directory(p.join(repo.path, '.git')).createSync();
        File(
          p.join(repo.path, '.git', 'config'),
        ).writeAsStringSync('url = git@github.com:org1/repo1.git');

        var infos = await getAllRepoInfos(oceanWorkspace.path);

        expect(infos, hasLength(1));
        expect(infos.first.name, 'repo1');
        expect(infos.first.organization, 'org1');
        expect(infos.first.version, 'v.2.0.0');
      });
    });
  });
}
