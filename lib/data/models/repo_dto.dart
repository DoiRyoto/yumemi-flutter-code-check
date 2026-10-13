import 'package:json_annotation/json_annotation.dart';
import 'package:yumemi_flutter_code_check/domain/models/repo.dart';

part 'repo_dto.g.dart';

/// `GET /search/repositories` のレスポンス。
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class RepoSearchResponseDto {
  const RepoSearchResponseDto({
    required this.totalCount,
    required this.incompleteResults,
    required this.items,
  });

  factory RepoSearchResponseDto.fromJson(Map<String, dynamic> json) =>
      _$RepoSearchResponseDtoFromJson(json);

  final int totalCount;

  /// 検索がタイムアウトして部分結果になった場合に `true`。
  final bool incompleteResults;

  final List<RepoItemDto> items;
}

/// 検索結果の 1 件。API は 80 以上のフィールドを返すが、使うものだけ定義する。
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class RepoItemDto {
  const RepoItemDto({
    required this.fullName,
    required this.owner,
    required this.stargazersCount,
    this.language,
    this.description,
  });

  factory RepoItemDto.fromJson(Map<String, dynamic> json) =>
      _$RepoItemDtoFromJson(json);

  final String fullName;
  final OwnerDto owner;
  final int stargazersCount;
  final String? language;
  final String? description;

  Repo toDomain() => Repo(
    fullName: fullName,
    ownerAvatarUrl: owner.avatarUrl,
    stars: stargazersCount,
    language: language,
    description: description,
  );
}

@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class OwnerDto {
  const OwnerDto({required this.avatarUrl});

  factory OwnerDto.fromJson(Map<String, dynamic> json) =>
      _$OwnerDtoFromJson(json);

  final String avatarUrl;
}

/// `GET /repos/{owner}/{repo}` のレスポンス。
///
/// search API の `watchers_count` は star 数のエイリアスなので使わず、
/// 購読者数である [subscribersCount] を Watcher 数として扱う。
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class RepoDetailDto {
  const RepoDetailDto({
    required this.fullName,
    required this.owner,
    required this.stargazersCount,
    required this.subscribersCount,
    required this.forksCount,
    required this.openIssuesCount,
    this.language,
    this.description,
  });

  factory RepoDetailDto.fromJson(Map<String, dynamic> json) =>
      _$RepoDetailDtoFromJson(json);

  final String fullName;
  final OwnerDto owner;
  final int stargazersCount;
  final int subscribersCount;
  final int forksCount;
  final int openIssuesCount;
  final String? language;
  final String? description;

  RepoDetail toDomain() => RepoDetail(
    fullName: fullName,
    ownerAvatarUrl: owner.avatarUrl,
    stars: stargazersCount,
    watchers: subscribersCount,
    forks: forksCount,
    openIssues: openIssuesCount,
    language: language,
    description: description,
  );
}
