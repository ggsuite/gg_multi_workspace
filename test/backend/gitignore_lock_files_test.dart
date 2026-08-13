// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_multi_workspace/src/backend/gitignore_lock_files.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late Directory repoDir;
  late List<String> messages;

  /// The block every repository of the suite carries today.
  const dartLockBlock =
      '# Avoid committing pubspec.lock for library packages; '
      'see\n'
      '# https://dart.dev/guides/libraries/private-files#pubspeclock.\n'
      'pubspec.lock';

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gitignore_lock_files_test');
    repoDir = Directory(path.join(tmp.path, 'my_repo'))
      ..createSync(recursive: true);
    messages = <String>[];
  });

  tearDown(() {
    if (tmp.existsSync()) {
      tmp.deleteSync(recursive: true);
    }
  });

  File gitignore() => File(path.join(repoDir.path, '.gitignore'));

  void writeGitignore(String content) => gitignore().writeAsStringSync(content);

  void writeManifest(String name) =>
      File(path.join(repoDir.path, name)).writeAsStringSync('name: my_repo\n');

  bool run() =>
      ensureLockFilesNotIgnored(repoDir: repoDir, ggLog: messages.add);

  group('lockFileNamesFor', () {
    test('reports the lock files of every manifest lying in the repo', () {
      writeManifest('pubspec.yaml');
      expect(lockFileNamesFor(repoDir.path), <String>['pubspec.lock']);

      writeManifest('package.json');
      expect(lockFileNamesFor(repoDir.path), <String>[
        'pubspec.lock',
        'package-lock.json',
        'pnpm-lock.yaml',
        'yarn.lock',
      ]);
    });

    test('reports nothing for a repo without a known manifest', () {
      expect(lockFileNamesFor(repoDir.path), isEmpty);
    });

    test('reports a lock file that does not exist on disk yet', () {
      writeManifest('pubspec.yaml');

      expect(
        File(path.join(repoDir.path, 'pubspec.lock')).existsSync(),
        isFalse,
      );
      expect(lockFileNamesFor(repoDir.path), contains('pubspec.lock'));
    });
  });

  group('ensureLockFilesNotIgnored', () {
    test('removes the entry together with the comment block above it', () {
      writeManifest('pubspec.yaml');
      writeGitignore(
        '# Created by `dart pub`\n'
        '.dart_tool/\n'
        '\n'
        '$dartLockBlock\n'
        '\n'
        'coverage\n',
      );

      expect(run(), isTrue);
      expect(
        gitignore().readAsStringSync(),
        '# Created by `dart pub`\n'
        '.dart_tool/\n'
        '\n'
        '\n'
        'coverage\n',
      );
      expect(
        messages,
        contains('Removed the lock file entries from .gitignore of my_repo.'),
      );
    });

    test('removes the anchored form as well', () {
      writeManifest('pubspec.yaml');
      writeGitignore('build\n/pubspec.lock\ncoverage\n');

      expect(run(), isTrue);
      expect(gitignore().readAsStringSync(), 'build\ncoverage\n');
    });

    test('removes the TypeScript lock files of a bridge repo', () {
      writeManifest('pubspec.yaml');
      writeManifest('package.json');
      writeGitignore(
        'node_modules\n'
        'pubspec.lock\n'
        'pnpm-lock.yaml\n'
        'package-lock.json\n'
        'yarn.lock\n',
      );

      expect(run(), isTrue);
      expect(gitignore().readAsStringSync(), 'node_modules\n');
    });

    test('leaves pubspec.lock alone in a pure TypeScript repo', () {
      writeManifest('package.json');
      writeGitignore('pubspec.lock\npnpm-lock.yaml\n');

      expect(run(), isTrue);
      expect(gitignore().readAsStringSync(), 'pubspec.lock\n');
    });

    test('keeps a comment block that also introduces a kept entry', () {
      writeManifest('pubspec.yaml');
      writeGitignore(
        '# Generated files\n'
        'coverage\n'
        'pubspec.lock\n',
      );

      expect(run(), isTrue);
      expect(
        gitignore().readAsStringSync(),
        '# Generated files\n'
        'coverage\n',
      );
    });

    test('keeps foreign entries and does not touch a clean file', () {
      writeManifest('pubspec.yaml');
      writeGitignore('.dart_tool/\ncoverage\n');

      expect(run(), isFalse);
      expect(gitignore().readAsStringSync(), '.dart_tool/\ncoverage\n');
      expect(messages, isEmpty);
    });

    test('normalizes CRLF line endings while removing', () {
      writeManifest('pubspec.yaml');
      writeGitignore('build\r\npubspec.lock\r\ncoverage\r\n');

      expect(run(), isTrue);
      expect(gitignore().readAsStringSync(), 'build\ncoverage\n');
    });

    test('handles a file without a trailing newline', () {
      writeManifest('pubspec.yaml');
      writeGitignore('build\npubspec.lock');

      expect(run(), isTrue);
      expect(gitignore().readAsStringSync(), 'build\n');
    });

    test('empties a .gitignore that held nothing else', () {
      writeManifest('pubspec.yaml');
      writeGitignore('$dartLockBlock\n');

      expect(run(), isTrue);
      expect(gitignore().readAsStringSync(), isEmpty);
    });

    test('does not create a missing .gitignore', () {
      writeManifest('pubspec.yaml');

      expect(run(), isFalse);
      expect(gitignore().existsSync(), isFalse);
      expect(messages, isEmpty);
    });

    test('does nothing in a repo without a known manifest', () {
      writeGitignore('pubspec.lock\n');

      expect(run(), isFalse);
      expect(gitignore().readAsStringSync(), 'pubspec.lock\n');
      expect(messages, isEmpty);
    });
  });
}
