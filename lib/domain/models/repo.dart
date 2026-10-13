import 'package:freezed_annotation/freezed_annotation.dart';

part 'repo.freezed.dart';

/// 検索結果一覧に表示するリポジトリ。
@freezed
abstract class Repo with _$Repo {
  const factory Repo({
    required String fullName,
    required String ownerAvatarUrl,
    required int stars,
    String? language,
    String? description,
  }) = _Repo;
}

/// 詳細画面に表示するリポジトリ。
///
/// [watchers] は search API では取得できないため、[Repo] とは別の型にしている。
@freezed
abstract class RepoDetail with _$RepoDetail {
  const factory RepoDetail({
    required String fullName,
    required String ownerAvatarUrl,
    required int stars,
    required int watchers,
    required int forks,
    required int openIssues,
    String? language,
    String? description,
  }) = _RepoDetail;
}
