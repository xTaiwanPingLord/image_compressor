// 設定頁：語言、主題、色彩、字體切換，並確認會記住。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_compressor/ecommerce/state.dart';
import 'package:image_compressor/main.dart';
import 'package:image_compressor/normal/state.dart';
import 'package:image_compressor/settings/app_settings.dart';
import 'package:image_compressor/settings/theme.dart';
import 'package:image_compressor/src/rust/frb_generated.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> start(
  WidgetTester tester, {
  Color? systemColor,
}) async {
  SharedPreferences.setMockInitialValues({'app.language': 'zhTW'});
  final prefs = await SharedPreferences.getInstance();
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  await tester.pumpWidget(
    ImageCompressorApp(
      prefs: prefs,
      settings: AppSettings(prefs: prefs),
      systemColor: systemColor,
      ecom: EcomState(prefs: prefs),
      normal: NormalState(prefs: prefs),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('設定').first);
  await tester.pumpAndSettle();
  return prefs;
}

ThemeData currentTheme(WidgetTester tester) =>
    Theme.of(tester.element(find.text('MiSans TC')));

void main() {
  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        Platform.environment['IMGBRIDGE_LIB']!,
      ),
    );
  });

  testWidgets('語言切換', (tester) async {
    final prefs = await start(tester);
    expect(find.text('語言'), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('General'), findsOneWidget);
    expect(find.text('E-commerce'), findsOneWidget);
    expect(prefs.getString('app.language'), 'enUS');
    await tester.tap(find.text('简体中文'));
    await tester.pumpAndSettle();
    expect(find.text('语言'), findsOneWidget);
    expect(find.text('电商'), findsOneWidget);
    // 普通模式頁面也跟著翻譯
    await tester.tap(find.text('普通').first);
    await tester.pumpAndSettle();
    expect(find.text('全部压缩'), findsOneWidget);
    expect(find.text('拖放图片或文件夹到这里'), findsOneWidget);
  });

  testWidgets('主題、色彩、字體', (tester) async {
    final prefs = await start(tester);
    // 不支援系統色彩時不顯示該選項
    expect(find.text('跟隨系統色彩'), findsNothing);

    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(currentTheme(tester).brightness, Brightness.dark);
    expect(prefs.getString('app.themeMode'), 'dark');

    final before = currentTheme(tester).colorScheme.primary;
    await tester.tap(
      find.byType(InkWell).at(find.byType(InkWell).evaluate().length - 3),
    );
    await tester.pumpAndSettle();
    expect(currentTheme(tester).colorScheme.primary, isNot(before));
    expect(prefs.getInt('app.seed'), isNot(0));

    await tester.tap(find.text('MiSans TC'));
    await tester.pumpAndSettle();
    expect(currentTheme(tester).textTheme.bodyMedium?.fontFamily, miSansFamily);
    expect(prefs.getString('app.font'), 'miSans');
    await tester.tap(find.text('預設（系統字體）'));
    await tester.pumpAndSettle();
    expect(
      currentTheme(tester).textTheme.bodyMedium?.fontFamily,
      isNot(miSansFamily),
    );
  });

  testWidgets('跟隨系統色彩', (tester) async {
    const accent = Color(0xFFFF6600);
    final prefs = await start(tester, systemColor: accent);
    expect(find.text('跟隨系統色彩'), findsOneWidget);
    final seeded = currentTheme(tester).colorScheme.primary;
    await tester.tap(find.text('跟隨系統色彩'));
    await tester.pumpAndSettle();
    expect(prefs.getBool('app.systemColor'), isTrue);
    final sys = currentTheme(tester).colorScheme.primary;
    expect(sys, isNot(seeded));
    expect(sys, ColorScheme.fromSeed(seedColor: accent).primary);
  });
}
