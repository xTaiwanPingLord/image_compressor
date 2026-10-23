// 手機尺寸（412×915）版面截圖：普通 / 電商 / 設定，檢查沒有溢出。

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
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
    await tester.binding.setSurfaceSize(const Size(412, 915));
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
    await tester.tap(find.text('設定').last);
    await tester.pumpAndSettle();
    await _shot(tester, 'phone_settings');
    expect(tester.takeException(), isNull);
  });
}
