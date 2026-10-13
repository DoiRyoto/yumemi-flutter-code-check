import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yumemi_flutter_code_check/data/services/github_api.dart';
import 'package:yumemi_flutter_code_check/domain/exceptions/app_exception.dart';

/// 実際の API から取得したレスポンスを、使うフィールドだけに削ったもの。
const _searchJson = '''
{
  "total_count": 1072942,
  "incomplete_results": false,
  "items": [
    {
      "full_name": "flutter/flutter",
      "owner": { "avatar_url": "https://avatars.githubusercontent.com/u/14101776?v=4" },
      "stargazers_count": 178960,
      "language": "Dart",
      "description": "Flutter makes it easy and fast to build beautiful apps."
    }
  ]
}
''';

const _detailJson = '''
{
  "full_name": "flutter/flutter",
  "owner": { "avatar_url": "https://avatars.githubusercontent.com/u/14101776?v=4" },
  "stargazers_count": 178960,
  "subscribers_count": 3542,
  "forks_count": 31246,
  "open_issues_count": 13175,
  "language": null,
  "description": null
}
''';

GitHubApi apiReturning(
  String body, {
  int statusCode = 200,
  Map<String, String> headers = const {},
}) => GitHubApi(
  client: MockClient(
    (_) async => http.Response(body, statusCode, headers: headers),
  ),
);

void main() {
  group('searchRepos', () {
    test('レスポンスをドメインモデルに変換する', () async {
      final api = apiReturning(_searchJson);

      final response = await api.searchRepos('flutter');

      expect(response.totalCount, 1072942);
      expect(response.incompleteResults, isFalse);

      final repo = response.items.single.toDomain();
      expect(repo.fullName, 'flutter/flutter');
      expect(repo.stars, 178960);
      expect(repo.language, 'Dart');
      expect(repo.ownerAvatarUrl, startsWith('https://avatars.'));
    });

    test('キーワードと per_page をクエリに載せる', () async {
      late Uri requested;
      final api = GitHubApi(
        client: MockClient((request) async {
          requested = request.url;
          return http.Response(_searchJson, 200);
        }),
      );

      await api.searchRepos('dart lang', perPage: 50);

      expect(requested.host, 'api.github.com');
      expect(requested.path, '/search/repositories');
      expect(requested.queryParameters, {'q': 'dart lang', 'per_page': '50'});
    });
  });

  group('fetchRepoDetail', () {
    test('Watcher 数には subscribers_count を使う', () async {
      final api = apiReturning(_detailJson);

      final detail = (await api.fetchRepoDetail('flutter/flutter')).toDomain();

      // search API の watchers_count は star 数のエイリアスなので使わない。
      expect(detail.stars, 178960);
      expect(detail.watchers, 3542);
      expect(detail.forks, 31246);
      expect(detail.openIssues, 13175);
      expect(detail.language, isNull);
      expect(detail.description, isNull);
    });
  });

  group('ステータスコードの変換', () {
    test('422 -> InvalidQueryException', () {
      final api = apiReturning(
        '{"message": "Validation Failed"}',
        statusCode: 422,
      );

      expect(() => api.searchRepos(''), throwsA(isA<InvalidQueryException>()));
    });

    test('404 -> NotFoundException', () {
      final api = apiReturning('{"message": "Not Found"}', statusCode: 404);

      expect(
        () => api.fetchRepoDetail('no/such'),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('503 -> ServerException', () {
      final api = apiReturning('{}', statusCode: 503);

      expect(() => api.searchRepos('a'), throwsA(isA<ServerException>()));
    });

    test(
      '403 + x-ratelimit-remaining: 0 -> 復帰時刻つきの RateLimitException',
      () async {
        final reset = DateTime.now().add(const Duration(minutes: 1));
        final api = apiReturning(
          '{"message": "API rate limit exceeded"}',
          statusCode: 403,
          headers: {
            'x-ratelimit-remaining': '0',
            'x-ratelimit-reset': '${reset.millisecondsSinceEpoch ~/ 1000}',
          },
        );

        final exception = await api
            .searchRepos('a')
            .then<Object?>((_) => null, onError: (Object e) => e);

        expect(exception, isA<RateLimitException>());
        expect(
          (exception! as RateLimitException).retryAt!.millisecondsSinceEpoch,
          closeTo(reset.millisecondsSinceEpoch, 1000),
        );
      },
    );

    test('429 + retry-after -> 秒数から復帰時刻を求める', () async {
      final api = apiReturning(
        '{}',
        statusCode: 429,
        headers: {'retry-after': '60'},
      );

      final exception = await api
          .searchRepos('a')
          .then<Object?>((_) => null, onError: (Object e) => e);

      final retryAt = (exception! as RateLimitException).retryAt!;
      expect(retryAt.difference(DateTime.now()).inSeconds, closeTo(60, 2));
    });

    test('レート制限と分からない 403 -> ForbiddenException', () {
      // 非公開リポジトリや IP ブロックなど、待っても解消しない 403。
      final api = apiReturning(
        '{"message": "Must have admin rights to Repository."}',
        statusCode: 403,
      );

      expect(
        () => api.fetchRepoDetail('private/repo'),
        throwsA(isA<ForbiddenException>()),
      );
    });

    test('ヘッダが無くても本文で判断できる 403 -> RateLimitException', () async {
      // secondary rate limit は retry-after も x-ratelimit-remaining も
      // 付かないことがある。
      final api = apiReturning(
        '{"message": "You have exceeded a secondary rate limit."}',
        statusCode: 403,
      );

      final exception = await api
          .searchRepos('a')
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect(exception, isA<RateLimitException>());
      expect((exception! as RateLimitException).retryAt, isNull);
    });

    test('端末の時計がずれていても復帰時刻は 1 時間先までに抑える', () async {
      // x-ratelimit-reset は GitHub 側の時刻。端末の時計が 1 日遅れている状況。
      final farFuture = DateTime.now().add(const Duration(days: 1));
      final api = apiReturning(
        '{"message": "API rate limit exceeded"}',
        statusCode: 403,
        headers: {
          'x-ratelimit-remaining': '0',
          'x-ratelimit-reset': '${farFuture.millisecondsSinceEpoch ~/ 1000}',
        },
      );

      final exception = await api
          .searchRepos('a')
          .then<Object?>((_) => null, onError: (Object e) => e);

      final retryAt = (exception! as RateLimitException).retryAt!;
      expect(retryAt.difference(DateTime.now()).inMinutes, closeTo(60, 1));
    });

    test('未定義のステータス -> UnknownException', () {
      final api = apiReturning('{}', statusCode: 418);

      expect(() => api.searchRepos('a'), throwsA(isA<UnknownException>()));
    });
  });

  group('通信の失敗', () {
    test('壊れた JSON -> UnknownException', () {
      final api = apiReturning('<html>not json</html>');

      expect(() => api.searchRepos('a'), throwsA(isA<UnknownException>()));
    });

    test('期待と違う形の JSON -> UnknownException', () {
      final api = apiReturning(jsonEncode({'total_count': 'not a number'}));

      expect(() => api.searchRepos('a'), throwsA(isA<UnknownException>()));
    });

    test('SocketException -> NetworkException', () {
      final api = GitHubApi(
        client: MockClient((_) async => throw const SocketException('offline')),
      );

      expect(() => api.searchRepos('a'), throwsA(isA<NetworkException>()));
    });

    test('ClientException -> NetworkException', () {
      final api = GitHubApi(
        client: MockClient((_) async => throw http.ClientException('failed')),
      );

      expect(() => api.searchRepos('a'), throwsA(isA<NetworkException>()));
    });

    test('タイムアウト -> NetworkException', () {
      final api = GitHubApi(
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(seconds: 1));
          return http.Response(_searchJson, 200);
        }),
        timeout: const Duration(milliseconds: 10),
      );

      expect(() => api.searchRepos('a'), throwsA(isA<NetworkException>()));
    });
  });
}
