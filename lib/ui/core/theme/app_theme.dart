import 'package:flutter/material.dart';

abstract final class AppTheme {
  // TODO(design): 配色は未決定。ダークモードを動かすために置いている暫定値。
  static const Color seedColor = Color(0xFF6E5494);

  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    ),
  );
}
