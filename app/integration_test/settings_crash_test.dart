// 回歸測試：以電商模式啟動 → 開設定 → 取消 / 儲存，不可崩潰。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_compressor/ecommerce/state.dart';
import 'package:image_compressor/main.dart';
import 'package:image_compressor/normal/state.dart';
import 'package:image_compressor/src/rust/frb_generated.dart';
import 'package:image_compressor/widgets/hint.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => RustLib.init());

  for (final action in ['取消', '儲存']) {
    testWidgets('電商模式啟動後開設定再$action', (tester) async {
      SharedPreferences.setMockInitialValues({
        'app.mode': 1,
        'app.language': 'zhTW',
      });
      final prefs = await SharedPreferences.getInstance();
      await tester.binding.setSurfaceSize(const Size(1280, 860));
      await tester.pumpWidget(
        ImageCompressorApp(
          prefs: prefs,
          ecom: EcomState(prefs: prefs),
          normal: NormalState(prefs: prefs),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate((w) => w is Hint && w.message == '設定'),
      );
      await tester.pumpAndSettle();
      expect(find.text('電商模式設定'), findsOneWidget);
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      expect(find.text('電商模式設定'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
