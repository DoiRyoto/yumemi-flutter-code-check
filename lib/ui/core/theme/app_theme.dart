import 'package:flutter/material.dart';

/// アプリ全体のテーマ定義。
///
/// ライト / ダークで同じ [seedColor] から [ColorScheme] を生成することで、
/// 配色の一貫性と Material 3 が保証するコントラスト比の両方を得る。
abstract final class AppTheme {
  /// 配色の基準色。GitHub のブランドカラーに近い紫を採用している。
  static const Color seedColor = Color(0xFF6E5494);

  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );

    return ThemeData(
      colorScheme: colorScheme,
      // スクロール時に AppBar の色が変わると検索バーとの境界が曖昧になるため固定する。
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        scrolledUnderElevation: 0,
      ),
    );
  }
}
