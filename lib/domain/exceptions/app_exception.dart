/// アプリが扱う例外の基底。
///
/// データ層が `SocketException` や HTTP ステータスをこの型に変換するため、
/// UI 層は `dart:io` や `http` を知らないまま表示を切り替えられる。
/// `sealed` なので `switch` の網羅性がコンパイル時に検査される。
sealed class AppException implements Exception {
  const AppException();
}

/// 通信自体に失敗した（オフライン、名前解決の失敗、タイムアウト）。
final class NetworkException extends AppException {
  const NetworkException();
}

/// レート制限に達した（403 / 429）。
final class RateLimitException extends AppException {
  const RateLimitException({this.retryAt});

  /// 再試行が可能になる時刻。`x-ratelimit-reset` または `retry-after` から求める。
  /// どちらも取得できなかった場合は `null`。
  final DateTime? retryAt;
}

/// アクセスが拒否された（レート制限以外の 403）。
///
/// 非公開リポジトリ、IP ブロック、SAML 必須の組織など。待っても解消しない。
final class ForbiddenException extends AppException {
  const ForbiddenException();
}

/// 検索条件が受け付けられなかった（422）。
final class InvalidQueryException extends AppException {
  const InvalidQueryException();
}

/// リポジトリが存在しない（404）。
final class NotFoundException extends AppException {
  const NotFoundException();
}

/// サーバ側のエラー（5xx。search の 503 を含む）。
final class ServerException extends AppException {
  const ServerException();
}

/// 上記に当てはまらないエラー。レスポンスの解釈失敗もここに含める。
final class UnknownException extends AppException {
  const UnknownException(this.error);

  final Object error;
}
