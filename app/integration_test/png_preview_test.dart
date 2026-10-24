// 回歸測試：大圖輸出 PNG（目標大小模式）時預覽與清單不可出現錯誤 widget。

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_compressor/ecommerce/state.dart';
import 'package:image_compressor/l10n/l10n.dart';
import 'package:image_compressor/main.dart';
import 'package:image_compressor/normal/state.dart';
import 'package:image_compressor/settings/app_settings.dart';
import 'package:image_compressor/src/rust/api/normal.dart';
import 'package:image_compressor/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

final _key = GlobalKey();

Future<void> _wait(WidgetTester tester, bool Function() done) async {
  final end = DateTime.now().add(const Duration(seconds: 300));
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('timeout');
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => RustLib.init());

  testWidgets('PNG preview of a large image', (tester) async {
    final src = Platform.environment['IMGC_PNG_IMAGE'];
    if (src == null) {
      markTestSkipped('IMGC_PNG_IMAGE not set');
      return;
    }
    final normal = NormalState();
    normal.settings
      ..format = OutFormat.png
      ..maxSize = 500 * 1000;
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(
      RepaintBoundary(
        key: _key,
        child: MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: appTheme(Brightness.dark),
          home: HomeShell(
            settings: AppSettings(),
            ecom: EcomState(),
            normal: normal,
          ),
        ),
      ),
    );
    await tester.runAsync(() => normal.addPaths([src]));
    await _wait(tester, () => normal.items.every((i) => i.loaded));
    await _wait(
      tester,
      () => normal.preview.result != null || normal.preview.error != null,
    );
    await tester.runAsync(() => Future.delayed(const Duration(seconds: 3)));
    await tester.pump();
    await tester.runAsync(() async {
      final b =
          _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 1);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      final dir =
          Platform.environment['IMGC_SHOT_DIR'] ?? Directory.systemTemp.path;
      await File(
        p.join(dir, 'png_preview.png'),
      ).writeAsBytes(bytes!.buffer.asUint8List());
    });
    expect(normal.preview.error, isNull);
    expect(tester.takeException(), isNull);
  });
}
