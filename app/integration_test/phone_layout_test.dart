// 手機尺寸（412×915）版面截圖：普通 / 電商 / 設定，檢查沒有溢出。

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_compressor/ecommerce/dialogs.dart';
import 'package:image_compressor/ecommerce/page.dart';
import 'package:image_compressor/ecommerce/state.dart';
import 'package:image_compressor/main.dart';
import 'package:image_compressor/normal/state.dart';
import 'package:image_compressor/settings/app_settings.dart';
import 'package:image_compressor/src/rust/api/ecommerce.dart';
import 'package:image_compressor/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

final _key = GlobalKey();

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.runAsync(() => Future.delayed(const Duration(seconds: 3)));
  await tester.pump();
  await tester.runAsync(() async {
    final b = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final dir =
        Platform.environment['IMGC_SHOT_DIR'] ?? Directory.systemTemp.path;
    await File(p.join(dir, '$name.png'))
        .writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => RustLib.init());

  testWidgets('phone layout', (tester) async {
    SharedPreferences.setMockInitialValues({'app.language': 'zhTW'});
    final prefs = await SharedPreferences.getInstance();
    final normal = NormalState(prefs: prefs);
    final ecom = EcomState(prefs: prefs);
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: _key,
        child: ImageCompressorApp(
          prefs: prefs,
          settings: AppSettings(prefs: prefs),
          ecom: ecom,
          normal: normal,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final src = Platform.environment['IMGC_TEST_IMAGES'];
    if (src != null) {
      await tester.runAsync(
        () => normal.addPaths([
          p.join(src, 'cooling_laird_7.jpg'),
          p.join(src, 'cooling_laird_14.jpg'),
        ]),
      );
      await tester.runAsync(() async {
        await ecom.addPaths(ImgCategory.main, [
          p.join(src, 'cooling_laird_7.jpg'),
          p.join(src, 'cooling_laird_8.jpg'),
        ]);
      });
    }
    await _shot(tester, 'phone_normal');
    await tester.tap(find.text('電商'));
    await tester.pumpAndSettle();
    await _shot(tester, 'phone_ecom');
    // 電商設定：窄螢幕為底部彈出
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await _shot(tester, 'phone_ecom_settings');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    // 結果對話框：長檔名要省略
    final ctx = tester.element(find.byType(EcommercePage));
    showResult(
      ctx,
      EcomReport(
        outputRoot: '/tmp/out',
        descCounts: const [],
        overflow: const [],
        outputs: [
          for (final c in [ImgCategory.main, ImgCategory.desc])
            OutputInfo(
              platform: ShopPlatform.shopee,
              category: c,
              fileName: '2B47831694A7EC6D761FCFC14DA8C_${c.name}_01.jpg',
              width: 2000,
              height: 2667,
              bytes: BigInt.from(232000),
              quality: 92,
              warnings: const [],
            ),
        ],
        writtenCount: 2,
        disposedCount: 0,
      ),
    );
    await tester.pumpAndSettle();
    await _shot(tester, 'phone_ecom_result');
    Navigator.of(ctx).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('設定').last);
    await tester.pumpAndSettle();
    await _shot(tester, 'phone_settings');
    expect(tester.takeException(), isNull);
  });
}
