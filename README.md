# yumemi_flutter_code_check

キーワードから GitHub のリポジトリを検索する Flutter アプリ（ゆめみ Flutter エンジニアコードチェック課題）。

> **Note**
> 現時点では環境構築のみが完了した状態です。以下の節は実装の進行に合わせて記述してください。
>
> - [ ] 概要・スクリーンショット / デモ
> - [ ] 設計（アーキテクチャ、状態管理の方針、ディレクトリ構成）
> - [ ] アピールポイント
> - [ ] AI サービスの利用について（利用したプロンプト等）

## 開発環境

| 項目 | バージョン |
| --- | --- |
| Flutter | 3.47.3 (stable) |
| Dart | 3.13.3 |

課題要件どおり最新の安定版を使用しています。バージョンは [`.fvmrc`](.fvmrc) で固定しており、
ローカル（[fvm](https://fvm.app/)）と CI がこのファイルを唯一の情報源として参照します。

## セットアップ

```bash
# 1. 指定バージョンの Flutter SDK を取得（fvm を使わない場合はこの手順は不要）
fvm install

# 2. 依存パッケージを取得
fvm flutter pub get

# 3. 多言語化クラスを生成（lib/l10n/*.arb -> lib/l10n/gen/）
fvm flutter gen-l10n

# 4. コードを生成（freezed / json_serializable / riverpod_generator）
fvm dart run build_runner build --delete-conflicting-outputs

# 5. 実行
fvm flutter run
```

> **Note**
> 生成物（`*.freezed.dart` / `*.g.dart` / `lib/l10n/gen/`）はリポジトリに含めず、
> セットアップ時と CI で毎回生成する方針です。そのため手順 3・4 は初回に必ず実行してください。

## 開発時によく使うコマンド

```bash
# コード生成をファイル変更に追従させる（開発中はこれを起動しておく）
fvm dart run build_runner watch --delete-conflicting-outputs

# フォーマット / 静的解析 / テスト（CI と同じ内容）
fvm dart format $(git ls-files '*.dart')
fvm flutter analyze --fatal-infos
fvm flutter test
```

## 使用パッケージ

| パッケージ | 用途 |
| --- | --- |
| `flutter_riverpod` / `riverpod_annotation` / `riverpod_generator` | 状態管理（課題要件） |
| `http` | GitHub API 呼び出し（要件によりラッパーを使わず自前実装するため薄い HTTP クライアントのみ） |
| `freezed` / `json_serializable` | イミュータブルなモデルと JSON デシリアライズ |
| `intl` / `flutter_localizations` | 多言語対応・数値整形 |
| `mocktail` | テストダブル |

## CI

[GitHub Actions](.github/workflows/ci.yaml) で以下を実行します。

| ジョブ | 内容 |
| --- | --- |
| `verify` | 依存解決 → コード生成 → 翻訳漏れ検査 → フォーマット検査 → 静的解析 → テスト（カバレッジ取得） |
| `build` | Android APK / Web / iOS（署名なし）のリリースビルドを並列実行 |
| `deploy` | `main` への push 時に Web 版を GitHub Pages へ公開（仮のデプロイ環境） |

使用する Flutter のバージョンは `subosito/flutter-action` の `flutter-version-file` で
[`.fvmrc`](.fvmrc) から直接読み取るため、ローカルと CI で二重管理になりません。

> **Note**
> `deploy` ジョブを動かすには、リポジトリの **Settings > Pages > Source** を
> **GitHub Actions** に設定しておく必要があります。
