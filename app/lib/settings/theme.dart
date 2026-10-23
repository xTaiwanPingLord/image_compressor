import 'package:flutter/material.dart';

import 'app_settings.dart';

/// 內建字體家族名稱（pubspec.yaml fonts）
const miSansFamily = 'MiSans TC';
const miSansScFamily = 'MiSans';

/// MiSans 依語言選主字體：簡體用 MiSans（簡體字形），其他用 MiSans TC；互為備援。
String miSansPrimary(AppLanguage lang) => lang == AppLanguage.zhCN ? miSansScFamily : miSansFamily;
String miSansSecondary(AppLanguage lang) => lang == AppLanguage.zhCN ? miSansFamily : miSansScFamily;

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
  final family = miSans ? miSansPrimary(settings.language) : null;
  final fallback = [
    if (miSans) miSansSecondary(settings.language),
    ..._systemFallback(settings.language),
  ];
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: family,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: family,
      fontFamilyFallback: fallback,
    ),
    primaryTextTheme: base.primaryTextTheme.apply(
      fontFamily: family,
      fontFamilyFallback: fallback,
    ),
    // Slider 的數值泡泡用 OverlayPortal，Windows 無障礙橋接有崩潰風險（flutter/flutter#182444）
    sliderTheme: base.sliderTheme.copyWith(
      showValueIndicator: ShowValueIndicator.never,
    ),
  );
}
