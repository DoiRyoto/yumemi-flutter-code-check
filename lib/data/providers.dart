import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:yumemi_flutter_code_check/data/repositories/repo_repository.dart';
import 'package:yumemi_flutter_code_check/data/services/github_api.dart';

part 'providers.g.dart';

@Riverpod(keepAlive: true)
http.Client httpClient(Ref ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
}

@Riverpod(keepAlive: true)
GitHubApi gitHubApi(Ref ref) =>
    GitHubApi(client: ref.watch(httpClientProvider));

/// キャッシュを保持し続ける必要があるため、破棄させない。
@Riverpod(keepAlive: true)
RepoRepository repoRepository(Ref ref) =>
    RepoRepository(ref.watch(gitHubApiProvider));
