import 'package:flutter/material.dart';

import 'app_settings.dart';

/// 內建 MiSans TC 的字體家族名稱（pubspec.yaml fonts）
const miSansFamily = 'MiSans TC';

/// 依語言挑選系統中文字體，避免繁簡字形混用。
List<String> _systemFallback(AppLanguage lang) => switch (lang) {
  AppLanguage.zhCN => const [
    'Microsoft YaHei UI',
    'Microsoft YaHei',
    'PingFang SC',
    'Noto Sans CJK SC',
    'Noto Sans SC',
  ],
  _ => const [
    'Microsoft JhengHei UI',
    'Microsoft JhengHei',
    'PingFang TC',
    'Noto Sans CJK TC',
    'Noto Sans TC',
  ],
};

ThemeData buildTheme({
  required Brightness brightness,
  required AppSettings settings,
  ColorScheme? dynamicScheme,
}) {
  final scheme =
      dynamicScheme ??
      ColorScheme.fromSeed(seedColor: settings.seed, brightness: brightness);
  final miSans = settings.font == AppFont.miSans;
  final fallback = _systemFallback(settings.language);
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: miSans ? miSansFamily : null,
  );
  return base.copyWith(
    // MiSans TC 只有繁體字形；缺字（例如簡體）時改用系統字體
    textTheme: base.textTheme.apply(
      fontFamily: miSans ? miSansFamily : null,
      fontFamilyFallback: fallback,
    ),
    primaryTextTheme: base.primaryTextTheme.apply(
      fontFamily: miSans ? miSansFamily : null,
      fontFamilyFallback: fallback,
    ),
    // Slider 的數值泡泡用 OverlayPortal，Windows 無障礙橋接有崩潰風險（flutter/flutter#182444）
    sliderTheme: base.sliderTheme.copyWith(
      showValueIndicator: ShowValueIndicator.never,
    ),
  );
}
