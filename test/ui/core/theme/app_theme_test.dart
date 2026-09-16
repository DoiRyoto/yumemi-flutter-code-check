import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yumemi_flutter_code_check/ui/core/theme/app_theme.dart';

void main() {
  group('AppTheme', () {
    test('ライト / ダークで対応する Brightness の ColorScheme を持つ', () {
      expect(AppTheme.light.colorScheme.brightness, Brightness.light);
      expect(AppTheme.dark.colorScheme.brightness, Brightness.dark);
    });

    test('ライト / ダークで配色が入れ替わる', () {
      expect(
        AppTheme.light.colorScheme.surface,
        isNot(AppTheme.dark.colorScheme.surface),
      );
    });
  });
}
