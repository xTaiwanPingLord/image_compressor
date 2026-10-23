// 設定頁與多語系截圖（實際 Linux 視窗，含真實字體渲染）。

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_compressor/ecommerce/state.dart';
import 'package:image_compressor/main.dart';
import 'package:image_compressor/normal/state.dart';
import 'package:image_compressor/settings/app_settings.dart';
import 'package:image_compressor/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

final _key = GlobalKey();

Future<void> _shot(WidgetTester tester, String name) async {
  final dir =
      Platform.environment['IMGC_SHOT_DIR'] ?? Directory.systemTemp.path;
  await tester.pump(const Duration(milliseconds: 300));
  await tester.runAsync(() async {
    final b = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    await File(p.join(dir, '$name.png'))
        .writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => RustLib.init());

  testWidgets('settings screenshots', (tester) async {
    SharedPreferences.setMockInitialValues({
      'app.language': 'zhTW',
      'app.font': 'miSans',
    });
    final prefs = await SharedPreferences.getInstance();
    final settings = AppSettings(prefs: prefs);
    final normal = NormalState(prefs: prefs);
    await tester.binding.setSurfaceSize(const Size(1280, 860));
    await tester.pumpWidget(
      RepaintBoundary(
        key: _key,
        child: ImageCompressorApp(
          prefs: prefs,
          settings: settings,
          ecom: EcomState(prefs: prefs),
          normal: normal,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('設定').first);
    await tester.pumpAndSettle();
    await _shot(tester, 'settings_zhTW_misans');

    settings
      ..setLanguage(AppLanguage.enUS)
      ..setThemeMode(ThemeMode.dark)
      ..setFont(AppFont.system)
      ..setSeed(7);
    await tester.pumpAndSettle();
    await _shot(tester, 'settings_en_dark');

    settings
      ..setLanguage(AppLanguage.zhCN)
      ..setThemeMode(ThemeMode.light)
      ..setFont(AppFont.miSans)
      ..setSeed(1);
    final src = Platform.environment['IMGC_TEST_IMAGES'];
    if (src != null) {
      await tester.runAsync(
        () => normal.addPaths([
          p.join(src, 'cooling_laird_7.jpg'),
          p.join(src, 'cooling_laird_14.jpg'),
        ]),
      );
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text('普通').first);
    await tester.pumpAndSettle();
    for (var i = 0; i < 40 && (normal.preview.result == null); i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump();
    }
    await tester.runAsync(() => Future.delayed(const Duration(seconds: 3)));
    await tester.pump();
    await _shot(tester, 'normal_zhCN_misans');
  });
}
