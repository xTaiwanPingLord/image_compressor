import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ecommerce/page.dart';
import 'ecommerce/state.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final prefs = await SharedPreferences.getInstance();
  runApp(ImageCompressorApp(ecom: EcomState(prefs: prefs)));
}

const _fontFallback = [
  'Microsoft JhengHei UI',
  'Microsoft JhengHei',
  'PingFang TC',
  'Noto Sans CJK TC',
  'Noto Sans TC',
];

ThemeData _theme(Brightness b) {
  final base = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF2E6BE6),
      brightness: b,
    ),
    useMaterial3: true,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamilyFallback: _fontFallback),
  );
}

class ImageCompressorApp extends StatelessWidget {
  const ImageCompressorApp({super.key, required this.ecom});
  final EcomState ecom;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '圖片壓縮',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: Scaffold(
        body: SafeArea(child: EcommercePage(state: ecom)),
      ),
    );
  }
}
