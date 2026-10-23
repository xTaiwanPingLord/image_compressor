// 端對端：用真實圖片驅動 UI 狀態並執行，輸出截圖。
//
// 圖片資料夾由環境變數 IMGC_TEST_IMAGES 指定（含 cooling_laird_7..16.jpg）。
// 截圖存到 IMGC_SHOT_DIR（預設系統暫存資料夾）。

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_compressor/ecommerce/dialogs.dart';
import 'package:image_compressor/ecommerce/page.dart';
import 'package:image_compressor/ecommerce/state.dart';
import 'package:image_compressor/src/rust/api/ecommerce.dart';
import 'package:image_compressor/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

final _shotKey = GlobalKey();

Future<void> _shot(WidgetTester tester, String name) async {
  final dir =
      Platform.environment['IMGC_SHOT_DIR'] ?? Directory.systemTemp.path;
  await tester.runAsync(() async {
    final boundary =
        _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(p.join(dir, '$name.png'))
        .writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Future<void> _settle(
  WidgetTester tester,
  bool Function() done, {
  int seconds = 120,
}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
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

  testWidgets('電商模式：加入實際圖片並執行', (tester) async {
    final src = Platform.environment['IMGC_TEST_IMAGES'];
    if (src == null) {
      markTestSkipped('未設定 IMGC_TEST_IMAGES');
      return;
    }
    // 複製到暫存資料夾，避免動到來源
    final work = Directory.systemTemp.createTempSync('imgc_e2e_');
    for (var i = 7; i <= 16; i++) {
      File(p.join(src, 'cooling_laird_$i.jpg'))
          .copySync(p.join(work.path, 'cooling_laird_$i.jpg'));
    }
    String f(int i) => p.join(work.path, 'cooling_laird_$i.jpg');

    final state = EcomState();
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    await tester.pumpWidget(
      RepaintBoundary(
        key: _shotKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2E6BE6),
            ),
            textTheme: Typography.blackMountainView.apply(
              fontFamilyFallback: ['Noto Sans CJK TC'],
            ),
          ),
          home: Scaffold(body: EcommercePage(state: state)),
        ),
      ),
    );

    // 故意亂序加入，確認自然排序；詳情圖一次加入
    await tester.runAsync(() async {
      await state.addPaths(ImgCategory.main, [f(10), f(8), f(7), f(9)]);
      await state.addPaths(ImgCategory.variant, [f(13), f(11), f(12)]);
      await state.addPaths(ImgCategory.desc, [f(16), f(14), f(15)]);
    });
    await _settle(tester, () => state.allLoaded);
    expect(state.name, 'cooling_laird');
    expect(state.sections[ImgCategory.main]!.map((e) => e.name).toList(), [
      'cooling_laird_7.jpg',
      'cooling_laird_8.jpg',
      'cooling_laird_9.jpg',
      'cooling_laird_10.jpg',
    ]);

    // 跨區拖移：把 variant 第 1 張移到 main 最前面，再移回去
    final v = state.sections[ImgCategory.variant]!.first;
    state.move(v, ImgCategory.main, index: 0);
    expect(state.sections[ImgCategory.main]!.first, v);
    state.move(v, ImgCategory.variant, index: 0);
    expect(state.sections[ImgCategory.variant]!.first, v);

    // 等縮圖產生
    await tester.runAsync(() => Future.delayed(const Duration(seconds: 8)));
    await tester.pump();
    await _shot(tester, 'ecom_loaded');

    // 開智慧切點後執行
    state.updateSettings(
      EcomSettings(
        shopeeMaxDesc: 12,
        momoMaxDesc: 18,
        smartCut: true,
        shopeeMaxWidth: 2000,
        momoMinLast: 300,
      ),
      Fit.pad,
    );
    EcomProgress? res;
    await tester.runAsync(() async {
      res = await state.run();
    });
    await tester.pump();
    expect(res!.stage, EcomStage.done, reason: res!.error);
    final r = res!.report!;
    expect(r.overflow, isEmpty);
    expect(r.outputs.length, 21);
    expect(r.writtenCount, 21);
    expect(Directory(p.join(work.path, 'momo')).listSync().length, 11);
    expect(Directory(p.join(work.path, 'shopee')).listSync().length, 10);

    // 結果對話框截圖
    final ctx = tester.element(find.byType(EcommercePage));
    showResult(ctx, r);
    await tester.pumpAndSettle();
    await _shot(tester, 'ecom_result');
    Navigator.of(ctx).pop();
    await tester.pumpAndSettle();

    // 預檢超量：momo 上限設 2 → 整批不輸出
    state.updateSettings(
      EcomSettings(
        shopeeMaxDesc: 12,
        momoMaxDesc: 2,
        smartCut: true,
        shopeeMaxWidth: 2000,
        momoMinLast: 300,
      ),
      Fit.pad,
    );
    await tester.runAsync(() async {
      res = await state.run();
    });
    expect(res!.report!.overflow.single.platform, ShopPlatform.momo);
    expect(res!.report!.writtenCount, 0);
    showOverflow(ctx, res!.report!);
    await tester.pumpAndSettle();
    await _shot(tester, 'ecom_overflow');
    Navigator.of(ctx).pop();
    await tester.pumpAndSettle();

    work.deleteSync(recursive: true);
  });
}
