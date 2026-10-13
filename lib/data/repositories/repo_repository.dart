import 'dart:async';

import 'package:yumemi_flutter_code_check/data/services/github_api.dart';
import 'package:yumemi_flutter_code_check/domain/exceptions/app_exception.dart';
import 'package:yumemi_flutter_code_check/domain/models/repo.dart';

/// リポジトリ検索のデータ取得口。
///
/// 未認証の search API は 10 リクエスト / 分と厳しいため、この層で
/// キャッシュとレート制限ゲートを持ち、無駄なリクエストを発生させない。
class RepoRepository {
  RepoRepository(
    this._api, {
    this.ttl = const Duration(minutes: 5),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// 復帰時刻が分からないまま制限された場合に待つ時間。
  ///
  /// GitHub のドキュメントが「手がかりが無い場合は最低 1 分待て」としている。
  static const _defaultCooldown = Duration(minutes: 1);

  final GitHubApi _api;

  /// キャッシュの有効期間。
  final Duration ttl;

  /// 現在時刻の取得。テストから時間を進めるために差し替えられるようにしている。
  final DateTime Function() _now;

  /// 解決済みの値ではなく [Future] を持つ。
  /// こうすると、同じキーへのリクエストが並行しても通信は 1 回で済む。
  final _searchCache = <String, _Cached<Future<List<Repo>>>>{};
  final _detailCache = <String, _Cached<Future<RepoDetail>>>{};

  /// レート制限が解除される時刻。制限されていなければ `null`。
  DateTime? _rateLimitedUntil;

  Future<List<Repo>> search(String keyword) {
    final key = keyword.trim();
    if (key.isEmpty) {
      // 空クエリは 422 が確定しているので、リクエストを消費しない。
      return Future.error(const InvalidQueryException());
    }

    return _cached(_searchCache, key, () async {
      final response = await _guard(() => _api.searchRepos(key));
      return List<Repo>.unmodifiable([
        for (final item in response.items) item.toDomain(),
      ]);
    });
  }

  Future<RepoDetail> detail(String fullName) =>
      _cached(_detailCache, fullName, () async {
        final dto = await _guard(() => _api.fetchRepoDetail(fullName));
        return dto.toDomain();
      });

  /// キャッシュがあればそれを返し、無ければ [fetch] の [Future] を覚えて返す。
  ///
  /// 失敗した [Future] は覚えたままにしない。エラーを握ったキャッシュが残ると、
  /// TTL の間ずっと同じエラーを返し続けてしまうため。
  Future<T> _cached<T>(
    Map<String, _Cached<Future<T>>> cache,
    String key,
    Future<T> Function() fetch,
  ) {
    final now = _now();
    cache.removeWhere((_, entry) => entry.isExpired(now));

    final cached = cache[key];
    if (cached != null) {
      return cached.value;
    }

    final future = fetch();
    cache[key] = _Cached(future, now.add(ttl));
    unawaited(
      future.then<void>((_) {}, onError: (Object _) => cache.remove(key)),
    );
    return future;
  }

  /// レート制限中はリクエストを送らずに例外を返す。
  ///
  /// 制限中にリクエストを送り続けると連携自体が BAN されうる、と
  /// GitHub のドキュメントが明記しているため。
  Future<T> _guard<T>(Future<T> Function() request) async {
    final until = _rateLimitedUntil;
    if (until != null) {
      if (_now().isBefore(until)) {
        throw RateLimitException(retryAt: until);
      }
      _rateLimitedUntil = null;
    }

    try {
      return await request();
    } on RateLimitException catch (e) {
      // 復帰時刻が分からなくてもゲートは閉じる。開けたままだと
      // 制限されたまま叩き続けることになる。
      _rateLimitedUntil = e.retryAt ?? _now().add(_defaultCooldown);
      rethrow;
    }
  }
}

class _Cached<T> {
  const _Cached(this.value, this.expiresAt);

  final T value;
  final DateTime expiresAt;

  bool isExpired(DateTime now) => !now.isBefore(expiresAt);
}
