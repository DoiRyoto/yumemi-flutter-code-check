# CLAUDE.md

## プロジェクト

ゆめみ Flutter エンジニアコードチェック課題。キーワードから GitHub リポジトリを検索するアプリ。
要件は [`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md) を参照。

## 開発コマンド

Flutter は fvm で管理し、バージョンは [`.fvmrc`](.fvmrc) に固定している。
**Flutter / Dart のコマンドは必ず `fvm` 経由で実行すること**（`dart` は PATH にない）。

```bash
fvm flutter pub get
fvm flutter gen-l10n                                          # lib/l10n/*.arb -> lib/l10n/gen/
fvm dart run build_runner build --delete-conflicting-outputs  # freezed / json_serializable / riverpod
fvm dart format $(git ls-files '*.dart')
fvm flutter analyze --fatal-infos
fvm flutter test
```

## 規約

- 生成物（`*.freezed.dart` / `*.g.dart` / `lib/l10n/gen/`）はコミットしない。編集するのは常に元ファイル側。
- 表示文言はハードコードせず `lib/l10n/app_ja.arb` と `app_en.arb` の両方に追加する。
- 状態管理は Riverpod（`@riverpod` によるコード生成）を使う。課題要件により Provider / Riverpod 以外は不可。
- GitHub API はラッパーパッケージを使わず `http` で自前実装する（課題要件）。
- `fvm flutter analyze --fatal-infos` が通ること。`analysis_options.yaml` で strict-casts などを有効化している。

## Proactive Flutter Hot Reload Rule

`lib/` 配下の `.dart` ファイルを編集・変更したときは常に:

1. **実行しない条件**
   - **`lib/` 外のファイル**: hot reload / hot restart は `lib/` 配下の編集に対してのみ実行する。他のディレクトリ（`test/**`、`integration_test/**`、`benchmark/**`、`test_driver/**`、`example/**` など）の変更では実行しない。
   - **コメント・ドキュメント**: 変更がコメント、docstring、空白のみに影響する場合は実行しない。

2. **検出と接続**
   - Dart MCP サーバーの `dtd` MCP ツール（または `list_running_apps` / `vm_service`）で実行中のアプリを検出する。

3. **hot reload / hot restart の実行**
   - UI ウィジェット（StatefulWidget の `build` メソッドを含む）や単純なメソッドを変更した直後は `hot_reload` MCP ツールを実行する。
   - 根本的なロジック、状態の初期化（`initState` など）、グローバル/静的な状態、`main()` を変更した場合は `hot_restart` MCP ツールを実行する。

> 出典: [flutter/agent-plugins](https://github.com/flutter/agent-plugins/blob/main/rules/flutter-hot-reload.md) (BSD-3-Clause)。
> Claude Code はプラグインの `rules/` を自動読み込みしないため、ここに転記している。
