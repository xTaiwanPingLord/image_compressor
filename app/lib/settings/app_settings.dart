import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage {
  zhTW(Locale('zh', 'TW'), '繁體中文'),
  zhCN(Locale('zh', 'CN'), '简体中文'),
  enUS(Locale('en', 'US'), 'English');

  const AppLanguage(this.locale, this.nativeName);
  final Locale locale;

  /// 以該語言本身書寫的名稱（不翻譯）
  final String nativeName;

  /// 依系統語系挑選預設語言。
  static AppLanguage fromSystem(List<Locale> locales) {
    for (final l in locales) {
      if (l.languageCode == 'zh') {
        final hans =
            l.scriptCode == 'Hans' || ['CN', 'SG'].contains(l.countryCode);
        return hans ? zhCN : zhTW;
      }
      if (l.languageCode == 'en') return enUS;
    }
    return zhTW;
  }
}

enum AppFont { system, miSans }

/// 預設色彩（第一個為預設藍）
const seedColors = <Color>[
  Color(0xFF2E6BE6), // 藍
  Color(0xFF00897B), // 青綠
  Color(0xFF43A047), // 綠
  Color(0xFFF9A825), // 黃
  Color(0xFFEF6C00), // 橙
  Color(0xFFE53935), // 紅
  Color(0xFFD81B60), // 粉
  Color(0xFF8E24AA), // 紫
  Color(0xFF5E35B1), // 靛
  Color(0xFF546E7A), // 灰藍
];

/// App 外觀與語言設定（自動記憶）。
class AppSettings extends ChangeNotifier {
  AppSettings({SharedPreferences? prefs}) : _prefs = prefs {
    final p = prefs;
    final lang = p?.getString(_kLang);
    language =
        AppLanguage.values.where((v) => v.name == lang).firstOrNull ??
        AppLanguage.fromSystem(PlatformDispatcher.instance.locales);
    themeMode =
        ThemeMode.values
            .where((v) => v.name == p?.getString(_kTheme))
            .firstOrNull ??
        ThemeMode.system;
    font =
        AppFont.values
            .where((v) => v.name == p?.getString(_kFont))
            .firstOrNull ??
        AppFont.system;
    useSystemColor = p?.getBool(_kSystemColor) ?? false;
    seedIndex = (p?.getInt(_kSeed) ?? 0).clamp(0, seedColors.length - 1);
  }

  static const _kLang = 'app.language';
  static const _kTheme = 'app.themeMode';
  static const _kFont = 'app.font';
  static const _kSeed = 'app.seed';
  static const _kSystemColor = 'app.systemColor';

  final SharedPreferences? _prefs;

  late AppLanguage language;
  late ThemeMode themeMode;
  late AppFont font;

  /// 跟隨系統色彩（Android 12+ 動態色彩、Windows / macOS 強調色）
  late bool useSystemColor;
  late int seedIndex;

  Color get seed => seedColors[seedIndex];

  void setLanguage(AppLanguage v) {
    language = v;
    _prefs?.setString(_kLang, v.name);
    notifyListeners();
  }

  void setThemeMode(ThemeMode v) {
    themeMode = v;
    _prefs?.setString(_kTheme, v.name);
    notifyListeners();
  }

  void setFont(AppFont v) {
    font = v;
    _prefs?.setString(_kFont, v.name);
    notifyListeners();
  }

  void setSeed(int i) {
    seedIndex = i.clamp(0, seedColors.length - 1);
    useSystemColor = false;
    _prefs?.setInt(_kSeed, seedIndex);
    _prefs?.setBool(_kSystemColor, false);
    notifyListeners();
  }

  void setUseSystemColor(bool v) {
    useSystemColor = v;
    _prefs?.setBool(_kSystemColor, v);
    notifyListeners();
  }
}
