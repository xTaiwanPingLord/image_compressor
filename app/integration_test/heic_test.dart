// HEIC：普通模式預覽 / 批次輸出 JPEG，並截圖（需系統 HEIF 解碼器；Linux 為 libheif）。
// 圖片取自 IMGC_HEIC_DIR（含 rot6.heic、plain.heic）。

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
import 'package:image_compressor/src/rust/api/files.dart';
import 'package:image_compressor/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

final _key = GlobalKey();

Future<void> _wait(WidgetTester tester, bool Function() done) async {
  final end = DateTime.now().add(const Duration(seconds: 120));
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('timeout');
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => RustLib.init());

  testWidgets('HEIC 預覽與輸出', (tester) async {
    final src = Platform.environment['IMGC_HEIC_DIR'];
    if (src == null || !await heifSupported()) {
      markTestSkipped('no HEIC samples / decoder');
      return;
    }
    final work = Directory.systemTemp.createTempSync('imgc_heic_');
    for (final f in ['rot6.heic', 'plain.heic']) {
      File(p.join(src, f)).copySync(p.join(work.path, f));
    }
    final normal = NormalState();
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(
      RepaintBoundary(
        key: _key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: appTheme(Brightness.light),
          home: HomeShell(
            settings: AppSettings(),
            ecom: EcomState(),
            normal: normal,
          ),
        ),
      ),
    );
    await tester.runAsync(() => normal.addPaths([work.path]));
    await _wait(tester, () => normal.items.every((i) => i.loaded));
    expect(normal.items.length, 2);
    final rot = normal.items.firstWhere((i) => i.name == 'rot6.heic');
    expect((rot.width, rot.height), (900, 1200));
    expect(rot.loadError, isNull);
    normal.select(rot.id);
    await _wait(
      tester,
      () => normal.preview.result != null || normal.preview.error != null,
    );
    expect(normal.preview.error, isNull);
    expect(normal.preview.result!.ext, 'jpg');
    expect(normal.preview.result!.height, 1200);
    await tester.runAsync(() => Future.delayed(const Duration(seconds: 4)));
    await tester.pump();
    await tester.runAsync(() async {
      final b =
          _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 1);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      final dir =
          Platform.environment['IMGC_SHOT_DIR'] ?? Directory.systemTemp.path;
      await File(p.join(dir, 'normal_heic.png'))
          .writeAsBytes(bytes!.buffer.asUint8List());
    });
    late BatchSummary sum;
    await tester.runAsync(() async => sum = await normal.run());
    expect(
      sum.failed,
      0,
      reason: normal.items.map((i) => i.error?.detail).join(),
    );
    expect(File(p.join(work.path, 'rot6_compressed.jpg')).existsSync(), isTrue);
    work.deleteSync(recursive: true);
  });
}
