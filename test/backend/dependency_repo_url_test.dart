// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_lang/gg_lang.dart';
import 'package:gg_multi_workspace/src/backend/dependency_repo_url.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('fetchDependencyRepoUrl', () {
    const packageName = 'test_pkg';

    test('throws exception when response status is not 200', () async {
      Future<http.Response> fakeFetcher(Uri uri) async {
        return http.Response('Not Found', 404);
      }

      expect(
        () async => await fetchDependencyRepoUrl(
          packageName,
          packageFetcher: fakeFetcher,
        ),
        throwsA(
          predicate(
            (e) =>
                e is Exception &&
                e.toString().contains(
                  'Failed to fetch package info '
                  'from pub.dev for $packageName',
                ),
          ),
        ),
      );
    });

    test('returns null when JSON does not contain latest key', () async {
      Future<http.Response> fakeFetcher(Uri uri) async {
        return http.Response('{}', 200);
      }

      final result = await fetchDependencyRepoUrl(
        packageName,
        packageFetcher: fakeFetcher,
      );
      expect(result, isNull);
    });

    test('returns null when latest exists but no pubspec key', () async {
      Future<http.Response> fakeFetcher(Uri uri) async {
        return http.Response('{"latest": {}}', 200);
      }

      final result = await fetchDependencyRepoUrl(
        packageName,
        packageFetcher: fakeFetcher,
      );
      expect(result, isNull);
    });

    test('returns null when pubspec exists but no repository key', () async {
      Future<http.Response> fakeFetcher(Uri uri) async {
        return http.Response('{"latest": {"pubspec": {}}}', 200);
      }

      final result = await fetchDependencyRepoUrl(
        packageName,
        packageFetcher: fakeFetcher,
      );
      expect(result, isNull);
    });

    test('returns repository URL when valid JSON provided', () async {
      const repoUrl = 'https://github.com/test_pkg/test_pkg.git';
      Future<http.Response> fakeFetcher(Uri uri) async {
        return http.Response(
          '{"latest": {"pubspec": {"repository": "$repoUrl"}}}',
          200,
        );
      }

      final result = await fetchDependencyRepoUrl(
        packageName,
        packageFetcher: fakeFetcher,
      );
      expect(result, equals(repoUrl));
    });

    group('for TypeScript (npm registry)', () {
      test('returns the repository URL from the object form, stripping '
          '"git+"', () async {
        Future<http.Response> fakeFetcher(Uri uri) async {
          expect(uri.toString(), contains('registry.npmjs.org'));
          return http.Response(
            '{"repository": {"type": "git", "url": '
            '"git+https://github.com/o/r.git"}}',
            200,
          );
        }

        final result = await fetchDependencyRepoUrl(
          packageName,
          type: ProjectType.typescript,
          packageFetcher: fakeFetcher,
        );
        expect(result, 'https://github.com/o/r.git');
      });

      test('returns the repository URL from the string form', () async {
        Future<http.Response> fakeFetcher(Uri uri) async {
          return http.Response('{"repository": "github:o/r"}', 200);
        }

        final result = await fetchDependencyRepoUrl(
          packageName,
          type: ProjectType.typescript,
          packageFetcher: fakeFetcher,
        );
        expect(result, 'github:o/r');
      });

      test('returns null when there is no repository field', () async {
        Future<http.Response> fakeFetcher(Uri uri) async {
          return http.Response('{"name": "test_pkg"}', 200);
        }

        final result = await fetchDependencyRepoUrl(
          packageName,
          type: ProjectType.typescript,
          packageFetcher: fakeFetcher,
        );
        expect(result, isNull);
      });

      test('throws when the npm response status is not 200', () async {
        Future<http.Response> fakeFetcher(Uri uri) async {
          return http.Response('Not Found', 404);
        }

        expect(
          () async => await fetchDependencyRepoUrl(
            packageName,
            type: ProjectType.typescript,
            packageFetcher: fakeFetcher,
          ),
          throwsA(
            predicate(
              (e) =>
                  e is Exception &&
                  e.toString().contains(
                    'Failed to fetch package info from npm '
                    'for $packageName',
                  ),
            ),
          ),
        );
      });
    });

    test('propagates exception from packageFetcher', () async {
      Future<http.Response> fakeFetcher(Uri uri) async {
        throw Exception('Fetcher error');
      }

      expect(
        () async => await fetchDependencyRepoUrl(
          packageName,
          packageFetcher: fakeFetcher,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('throws error when response body is invalid JSON', () async {
      Future<http.Response> fakeFetcher(Uri uri) async {
        return http.Response('invalid json', 200);
      }

      expect(
        () async => await fetchDependencyRepoUrl(
          packageName,
          packageFetcher: fakeFetcher,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws error when latest is not a map', () async {
      Future<http.Response> fakeFetcher(Uri uri) async {
        return http.Response('{"latest": "not a map"}', 200);
      }

      expect(
        () async => await fetchDependencyRepoUrl(
          packageName,
          packageFetcher: fakeFetcher,
        ),
        throwsA(isA<TypeError>()),
      );
    });

    test('throws error when pubspec is not a map', () async {
      Future<http.Response> fakeFetcher(Uri uri) async {
        return http.Response('{"latest": {"pubspec": "not a map"}}', 200);
      }

      expect(
        () async => await fetchDependencyRepoUrl(
          packageName,
          packageFetcher: fakeFetcher,
        ),
        throwsA(isA<TypeError>()),
      );
    });
  });
}
