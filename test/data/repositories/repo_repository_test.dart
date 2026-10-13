import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yumemi_flutter_code_check/data/repositories/repo_repository.dart';
import 'package:yumemi_flutter_code_check/data/services/github_api.dart';
import 'package:yumemi_flutter_code_check/domain/exceptions/app_exception.dart';

const _searchJson = '''
{
  "total_count": 1,
  "incomplete_results": false,
  "items": [
    {
      "full_name": "flutter/flutter",
      "owner": { "avatar_url": "https://example.com/a.png" },
      "stargazers_count": 1,
      "language": "Dart",
      "description": null
    }
  ]
}
''';

const _detailJson = '''
{
  "full_name": "flutter/flutter",
  "owner": { "avatar_url": "https://example.com/a.png" },
  "stargazers_count": 1,
  "subscribers_count": 2,
  "forks_count": 3,
  "open_issues_count": 4,
  "language": "Dart",
  "description": null
}
''';

void main() {
  /// 送信されたリクエスト数を数えられる [RepoRepository] を組み立てる。
  ({RepoRepository repository, List<Uri> requests}) build({
    required DateTime Function() now,
    http.Response Function(http.Request request)? respond,
    Future<void>? until,
  }) {
    final requests = <Uri>[];
    final api = GitHubApi(
      client: MockClient((request) async {
        requests.add(request.url);
        await until;
        return respond?.call(request) ??
            http.Response(
              request.url.path.startsWith('/search')
                  ? _searchJson
                  : _detailJson,
              200,
            );
      }),
    );
    return (repository: RepoRepository(api, now: now), requests: requests);
  }

  group('キャッシュ', () {
    test('同じキーワードの再検索では API を叩かない', () async {
      final clock = _Clock();
      final (:repository, :requests) = build(now: clock.now);

      final first = await repository.search('flutter');
      final second = await repository.search('flutter');

      expect(requests, hasLength(1));
      expect(second, first);
    });

    test('前後の空白を無視して同じキーワードとして扱う', () async {
      final clock = _Clock();
      final (:repository, :requests) = build(now: clock.now);

      await repository.search('flutter');
      await repository.search('  flutter  ');

      expect(requests, hasLength(1));
    });

    test('キーワードが違えば API を叩く', () async {
      final clock = _Clock();
      final (:repository, :requests) = build(now: clock.now);

      await repository.search('flutter');
      await repository.search('dart');

      expect(requests, hasLength(2));
    });

    test('TTL を過ぎたら API を叩き直す', () async {
      final clock = _Clock();
      final (:repository, :requests) = build(now: clock.now);

      await repository.search('flutter');
      clock.advance(const Duration(minutes: 5, seconds: 1));
      await repository.search('flutter');

      expect(requests, hasLength(2));
    });

    test('同じキーワードの検索が並行しても通信は 1 回', () async {
      final clock = _Clock();
      final gate = Completer<void>();
      final (:repository, :requests) = build(
        now: clock.now,
        until: gate.future,
      );

      // レスポンスが返る前に 2 回目を投げる（検索ボタンの連打に相当）。
      final first = repository.search('flutter');
      final second = repository.search('flutter');
      gate.complete();

      expect(await first, await second);
      expect(requests, hasLength(1));
    });

    test('空のキーワードではリクエストを送らない', () async {
      final clock = _Clock();
      final (:repository, :requests) = build(now: clock.now);

      await expectLater(
        repository.search('   '),
        throwsA(isA<InvalidQueryException>()),
      );

      expect(requests, isEmpty);
    });

    test('返すリストは変更できない', () async {
      final clock = _Clock();
      final repository = build(now: clock.now).repository;

      final repos = await repository.search('flutter');

      // UI 側で sort されるとキャッシュの中身が書き換わってしまうため。
      expect(repos.clear, throwsUnsupportedError);
    });

    test('失敗した結果はキャッシュしない', () async {
      final clock = _Clock();
      var failing = true;
      final (:repository, :requests) = build(
        now: clock.now,
        respond: (_) => failing
            ? http.Response('{}', 503)
            : http.Response(_searchJson, 200),
      );

      await expectLater(
        repository.search('flutter'),
        throwsA(isA<ServerException>()),
      );
      failing = false;
      final repos = await repository.search('flutter');

      expect(requests, hasLength(2));
      expect(repos, hasLength(1));
    });

    test('詳細も同様にキャッシュする', () async {
      final clock = _Clock();
      final (:repository, :requests) = build(now: clock.now);

      final first = await repository.detail('flutter/flutter');
      final second = await repository.detail('flutter/flutter');

      expect(requests, hasLength(1));
      expect(second, first);
      expect(first.watchers, 2);
    });
  });

  group('レート制限ゲート', () {
    /// 常に primary rate limit に達した状態を返す。
    http.Response rateLimited(DateTime reset) => http.Response(
      '{"message": "API rate limit exceeded"}',
      403,
      headers: {
        'x-ratelimit-remaining': '0',
        'x-ratelimit-reset': '${reset.millisecondsSinceEpoch ~/ 1000}',
      },
    );

    test('制限に達したあとはリクエストを送らずに例外を返す', () async {
      final clock = _Clock();
      final reset = clock.now().add(const Duration(minutes: 1));
      final (:repository, :requests) = build(
        now: clock.now,
        respond: (_) => rateLimited(reset),
      );

      await expectLater(
        repository.search('flutter'),
        throwsA(isA<RateLimitException>()),
      );
      await expectLater(
        repository.search('dart'),
        throwsA(isA<RateLimitException>()),
      );

      // 2 回目はゲートで止めるため、通信は 1 回だけ。
      expect(requests, hasLength(1));
    });

    test('復帰時刻を過ぎたらリクエストを再開する', () async {
      final clock = _Clock();
      final reset = clock.now().add(const Duration(minutes: 1));
      var limited = true;
      final (:repository, :requests) = build(
        now: clock.now,
        respond: (_) =>
            limited ? rateLimited(reset) : http.Response(_searchJson, 200),
      );

      await expectLater(
        repository.search('flutter'),
        throwsA(isA<RateLimitException>()),
      );

      clock.advance(const Duration(minutes: 1, seconds: 1));
      limited = false;
      final repos = await repository.search('flutter');

      expect(requests, hasLength(2));
      expect(repos.single.fullName, 'flutter/flutter');
    });

    test('復帰時刻が分からなくても既定のクールダウンでゲートを閉じる', () async {
      final clock = _Clock();
      var limited = true;
      final (:repository, :requests) = build(
        now: clock.now,
        respond: (_) => limited
            // secondary rate limit。ヘッダに手がかりが無い。
            ? http.Response(
                '{"message": "You have exceeded a secondary rate limit."}',
                403,
              )
            : http.Response(_searchJson, 200),
      );

      await expectLater(
        repository.search('flutter'),
        throwsA(isA<RateLimitException>()),
      );
      await expectLater(
        repository.search('dart'),
        throwsA(isA<RateLimitException>()),
      );
      expect(requests, hasLength(1));

      clock.advance(const Duration(minutes: 1, seconds: 1));
      limited = false;
      await repository.search('dart');

      expect(requests, hasLength(2));
    });

    test('レート制限以外のエラーではゲートを閉じない', () async {
      final clock = _Clock();
      final (:repository, :requests) = build(
        now: clock.now,
        respond: (_) => http.Response('{}', 503),
      );

      await expectLater(
        repository.search('flutter'),
        throwsA(isA<ServerException>()),
      );
      await expectLater(
        repository.search('flutter'),
        throwsA(isA<ServerException>()),
      );

      expect(requests, hasLength(2));
    });
  });
}

/// テストから進められる時計。
class _Clock {
  DateTime _value = DateTime(2026, 9, 16, 10);

  DateTime now() => _value;

  void advance(Duration duration) => _value = _value.add(duration);
}
