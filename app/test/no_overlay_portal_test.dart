// 回歸測試：Windows 無障礙橋接崩潰（flutter/flutter#182444）。
// Flutter 的 Tooltip / Slider 數值標籤用 OverlayPortal 嫁接 semantics，
// 在 Windows 有無障礙用戶端時會讓 flutter_windows.dll 崩潰。
// 確認整個 App 在各種操作下都不會出現 Tooltip / OverlayPortal。

import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_compressor/ecommerce/state.dart';
import 'package:image_compressor/main.dart';
import 'package:image_compressor/normal/state.dart';
import 'package:image_compressor/src/rust/frb_generated.dart';
import 'package:image_compressor/widgets/hint.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 不可有 Tooltip；OverlayPortal 只允許 Slider 內部（未使用的數值泡泡）。
void expectNoPortal([String where = '']) {
  expect(find.byType(Tooltip), findsNothing, reason: where);
  final stray = find
      .byType(OverlayPortal)
      .evaluate()
      .where(
        (e) => find
            .ancestor(
              of: find.byWidget(e.widget),
              matching: find.byType(Slider),
            )
            .evaluate()
            .isEmpty,
      )
      .toList();
  expect(stray, isEmpty, reason: 'Slider 以外的 OverlayPortal：$where');
}

Finder hint(String msg) =>
    find.byWidgetPredicate((w) => w is Hint && w.message == msg);

Future<void> hoverAllHints(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  for (final e in find.byType(Hint).hitTestable().evaluate().toList()) {
    final w = e.widget as Hint;
    if (w.message.isEmpty) continue;
    await mouse.moveTo(tester.getCenter(find.byWidget(w).first));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text(w.message), findsWidgets, reason: 'hint 應顯示：${w.message}');
    expectNoPortal(w.message);
  }
  await mouse.moveTo(Offset.zero);
  await tester.pump();
  await mouse.removePointer();
}

Future<void> start(WidgetTester tester, int mode) async {
  SharedPreferences.setMockInitialValues({
    'app.mode': mode,
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
}

void main() {
  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        Platform.environment['IMGBRIDGE_LIB']!,
      ),
    );
  });

  for (final action in ['取消', '儲存']) {
    testWidgets('電商模式啟動 → 設定 → $action', (tester) async {
      final handle = tester.ensureSemantics();
      await start(tester, 1);
      expectNoPortal();
      await hoverAllHints(tester);
      await tester.tap(hint('設定'));
      await tester.pumpAndSettle();
      expect(find.text('電商模式設定'), findsOneWidget);
      // 拖動品質上限 slider
      await tester.drag(find.byType(Slider).first, const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 100));
      expectNoPortal();
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      expect(find.text('電商模式設定'), findsNothing);
      expectNoPortal();
      handle.dispose();
    });
  }

  testWidgets('普通模式：hover、slider、切換模式', (tester) async {
    final handle = tester.ensureSemantics();
    await start(tester, 0);
    await hoverAllHints(tester);
    await tester.drag(find.byType(Slider).first, const Offset(-30, 0));
    await tester.pump(const Duration(milliseconds: 100));
    expectNoPortal();
    await tester.tap(find.text('輸出'));
    await tester.pumpAndSettle();
    expectNoPortal();
    await tester.tap(find.text('電商'));
    await tester.pumpAndSettle();
    await hoverAllHints(tester);
    expectNoPortal();
    handle.dispose();
  });
}
