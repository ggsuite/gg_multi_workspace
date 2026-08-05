// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_multi_workspace/src/backend/vscode_launcher.dart';
import 'package:test/test.dart';

void main() {
  group('VSCodeLauncher', () {
    test('launches VSCode with runInShell for directories', () async {
      final calls = <Map<String, Object?>>[];
      Future<void> fakeStarter(
        String exe,
        List<String> args, {
        bool runInShell = false,
      }) async {
        calls.add(<String, Object?>{
          'exe': exe,
          'args': args,
          'runInShell': runInShell,
        });
      }

      final launcher = VSCodeLauncher(processStarter: fakeStarter);
      final dir = Directory('/tmp/project');
      await launcher.open(dir);
      expect(calls.length, 1);
      expect(calls[0]['exe'], 'code');
      expect(calls[0]['args'], <String>[dir.path]);
      expect(calls[0]['runInShell'], isTrue);
    });

    test('launches VSCode with runInShell for arbitrary path', () async {
      final calls = <Map<String, Object?>>[];
      Future<void> fakeStarter(
        String exe,
        List<String> args, {
        bool runInShell = false,
      }) async {
        calls.add(<String, Object?>{
          'exe': exe,
          'args': args,
          'runInShell': runInShell,
        });
      }

      final launcher = VSCodeLauncher(processStarter: fakeStarter);
      const workspacePath = '/tmp/workspace.code-workspace';
      await launcher.openPath(workspacePath);
      expect(calls.length, 1);
      expect(calls[0]['exe'], 'code');
      expect(calls[0]['args'], <String>[workspacePath]);
      expect(calls[0]['runInShell'], isTrue);
    });

    test('propagates exception from starter', () async {
      Future<void> throwingStarter(
        String _,
        List<String> _, {
        bool runInShell = false,
      }) async {
        throw ArgumentError('fail');
      }

      final launcher = VSCodeLauncher(processStarter: throwingStarter);
      expect(
        () async => launcher.open(Directory('/tmp/xyz')),
        throwsA(
          isA<ArgumentError>().having((e) => e.message, 'message', 'fail'),
        ),
      );
    });
  });
}
