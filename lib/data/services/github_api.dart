import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:yumemi_flutter_code_check/data/models/repo_dto.dart';
import 'package:yumemi_flutter_code_check/domain/exceptions/app_exception.dart';

/// GitHub REST API の薄いクライアント。
///
/// 課題要件によりラッパーパッケージを使えないため `http` で自前実装している。
/// ここでは HTTP と JSON の関心事だけを扱い、キャッシュや再試行は
/// `RepoRepository` の責務とする。
class GitHubApi {
  GitHubApi({http.Client? client, this.timeout = const Duration(seconds: 15)})
    : _client = client ?? http.Client();

  static const _host = 'api.github.com';
  static const _headers = {
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  /// 復帰時刻として受け入れる上限。
  ///
  /// `x-ratelimit-reset` は GitHub 側の時刻なので、端末の時計が遅れていると
  /// 遠い未来の時刻になる。そのまま採用するとアプリを再起動するまで
  /// レート制限扱いが解けなくなるため、頭を押さえる。
  static const _maxRetryDelay = Duration(hours: 1);

  final http.Client _client;
  final Duration timeout;

  /// キーワードでリポジトリを検索する。
  Future<RepoSearchResponseDto> searchRepos(String query, {int perPage = 30}) {
    final uri = Uri.https(_host, '/search/repositories', {
      'q': query,
      'per_page': '$perPage',
    });
    return _get(uri, RepoSearchResponseDto.fromJson);
  }

  /// `owner/name` 形式のリポジトリの詳細を取得する。
  Future<RepoDetailDto> fetchRepoDetail(String fullName) {
    final uri = Uri.https(_host, '/repos/$fullName');
    return _get(uri, RepoDetailDto.fromJson);
  }

  Future<T> _get<T>(Uri uri, T Function(Map<String, dynamic>) fromJson) async {
    final http.Response response;
    try {
      response = await _client.get(uri, headers: _headers).timeout(timeout);
    } on SocketException {
      throw const NetworkException();
    } on http.ClientException {
      throw const NetworkException();
    } on TimeoutException {
      throw const NetworkException();
    }

    if (response.statusCode != HttpStatus.ok) {
      throw _toException(response);
    }

    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return fromJson(json);
    } on Object catch (error) {
      throw UnknownException(error);
    }
  }

  AppException _toException(http.Response response) {
    final code = response.statusCode;

    // 403 はレート制限以外（アクセス権限なし、IP ブロックなど）でも返るため、
    // レート制限であることを示す手がかりがある場合だけそう扱う。
    // 待てば直るのか、待っても無駄なのかで UI の出し方が変わる。
    if (code == HttpStatus.forbidden) {
      return _isRateLimited(response)
          ? RateLimitException(retryAt: _retryAt(response))
          : const ForbiddenException();
    }

    return switch (code) {
      HttpStatus.tooManyRequests => RateLimitException(
        retryAt: _retryAt(response),
      ),
      HttpStatus.unprocessableEntity => const InvalidQueryException(),
      HttpStatus.notFound => const NotFoundException(),
      >= HttpStatus.internalServerError => const ServerException(),
      _ => UnknownException('Unexpected status code: $code'),
    };
  }

  /// レート制限による拒否かどうか。
  ///
  /// primary は `x-ratelimit-remaining: 0`、secondary は `retry-after` が付く。
  /// どちらのヘッダも無い secondary もあるため、本文の文言も手がかりにする。
  bool _isRateLimited(http.Response response) =>
      response.headers['x-ratelimit-remaining'] == '0' ||
      response.headers.containsKey('retry-after') ||
      response.body.toLowerCase().contains('rate limit');

  /// 再試行が可能になる時刻。手がかりが無ければ `null`。
  DateTime? _retryAt(http.Response response) {
    final now = DateTime.now();

    final retryAfter = int.tryParse(response.headers['retry-after'] ?? '');
    if (retryAfter != null) {
      return _clamp(now.add(Duration(seconds: retryAfter)), now);
    }

    final remaining = response.headers['x-ratelimit-remaining'];
    final reset = int.tryParse(response.headers['x-ratelimit-reset'] ?? '');
    if (remaining == '0' && reset != null) {
      return _clamp(DateTime.fromMillisecondsSinceEpoch(reset * 1000), now);
    }

    return null;
  }

  DateTime _clamp(DateTime retryAt, DateTime now) {
    final limit = now.add(_maxRetryDelay);
    return retryAt.isAfter(limit) ? limit : retryAt;
  }
}
