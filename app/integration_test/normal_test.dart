// 普通模式端對端：真實圖片 → 預覽 → 批次壓縮，並輸出截圖。
// 需設定 IMGC_TEST_IMAGES；截圖存到 IMGC_SHOT_DIR。

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_compressor/ecommerce/state.dart';
import 'package:image_compressor/main.dart';
import 'package:image_compressor/normal/state.dart';
import 'package:image_compressor/settings/app_settings.dart';
import 'package:image_compressor/src/rust/api/normal.dart';
import 'package:image_compressor/l10n/l10n.dart';
import 'package:image_compressor/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

final _shotKey = GlobalKey();

Future<void> _shot(WidgetTester tester, String name) async {
  final dir =
      Platform.environment['IMGC_SHOT_DIR'] ?? Directory.systemTemp.path;
  await tester.runAsync(() async {
    final b =
        _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    await File(p.join(dir, '$name.png'))
        .writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Future<void> _wait(
  WidgetTester tester,
  bool Function() done, {
  int seconds = 180,
}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('timeout');
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump();
  }
}

Future<void> _idle(WidgetTester tester, int seconds) async {
  await tester.runAsync(() => Future.delayed(Duration(seconds: seconds)));
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => RustLib.init());

  testWidgets('普通模式：預覽與批次壓縮', (tester) async {
    final src = Platform.environment['IMGC_TEST_IMAGES'];
    if (src == null) {
      markTestSkipped('未設定 IMGC_TEST_IMAGES');
      return;
    }
    final work = Directory.systemTemp.createTempSync('imgc_normal_');
    final inDir = Directory(p.join(work.path, 'in', 'sub'))
      ..createSync(recursive: true);
    for (final i in [7, 11, 14]) {
      File(p.join(src, 'cooling_laird_$i.jpg'))
          .copySync(p.join(inDir.parent.path, 'cooling_laird_$i.jpg'));
    }
    File(p.join(src, 'cooling_laird_15.jpg'))
        .copySync(p.join(inDir.path, 'cooling_laird_15.jpg'));

    final normal = NormalState();
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(
      RepaintBoundary(
        key: _shotKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: appTheme(Brightness.light).copyWith(
            textTheme: appTheme(Brightness.light).textTheme
                .apply(fontFamilyFallback: ['Noto Sans CJK TC']),
          ),
          home: HomeShell(
            settings: AppSettings(),
            ecom: EcomState(),
            normal: normal,
          ),
        ),
      ),
    );

    // 加入資料夾（含子資料夾）
    await tester.runAsync(() => normal.addPaths([p.join(work.path, 'in')]));
    await _wait(tester, () => normal.items.every((i) => i.loaded));
    expect(normal.items.length, 4);
    expect(normal.items.last.name, 'cooling_laird_15.jpg'); // 子資料夾在後
    expect(normal.focused, isNotNull);

    // 預覽（預設 q80）
    await _wait(
      tester,
      () => normal.preview.result != null || normal.preview.error != null,
    );
    expect(normal.preview.error, isNull);
    final q80 = normal.preview.result!.data.length;
    expect(q80, lessThan(normal.focused!.originalSize));
    await _idle(tester, 6);
    await _shot(tester, 'normal_preview');

    // 改成 WebP + 長邊 1600 → 預覽更新
    normal.settings
      ..format = OutFormat.webp
      ..resize = ResizeMode.longEdge
      ..resizeValue = 1600;
    normal.settingsChanged();
    await _wait(tester, () => !normal.preview.loading);
    expect(normal.preview.result!.ext, 'webp');
    expect(normal.preview.result!.width, 1600);

    // 選第 3 張（詳情圖 4000×7998）
    normal.select(normal.items[2].id);
    await _wait(
      tester,
      () =>
          !normal.preview.loading &&
          normal.preview.itemId == normal.items[2].id,
    );
    expect(normal.preview.result!.height, 1600);

    // 批次：輸出到其他資料夾並保留結構
    final out = p.join(work.path, 'out');
    normal.settings
      ..outputDir = out
      ..keepStructure = true
      ..suffix = '';
    normal.settingsChanged();
    late BatchSummary sum;
    await tester.runAsync(() async => sum = await normal.run());
    await tester.pump();
    expect(sum.failed, 0, reason: normal.items.map((i) => i.error).join('\n'));
    expect(sum.done + sum.kept, 4);
    expect(File(p.join(out, 'cooling_laird_7.webp')).existsSync(), isTrue);
    expect(
      File(p.join(out, 'sub', 'cooling_laird_15.webp')).existsSync(),
      isTrue,
    );
    expect(sum.after, lessThan(sum.before));

    // 依節省排序
    normal.sortBy(SortColumn.saving);
    await _idle(tester, 4);
    await _shot(tester, 'normal_done');

    // 窄螢幕版面
    await tester.binding.setSurfaceSize(const Size(600, 900));
    await _idle(tester, 2);
    await _shot(tester, 'normal_narrow');

    work.deleteSync(recursive: true);
  });
}
