import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ecommerce/page.dart';
import 'ecommerce/state.dart';
import 'normal/page.dart';
import 'normal/state.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ImageCompressorApp(
      prefs: prefs,
      ecom: EcomState(prefs: prefs),
      normal: NormalState(prefs: prefs),
    ),
  );
}

const _fontFallback = [
  'Microsoft JhengHei UI',
  'Microsoft JhengHei',
  'PingFang TC',
  'Noto Sans CJK TC',
  'Noto Sans TC',
];

ThemeData appTheme(Brightness b) {
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
  const ImageCompressorApp({
    super.key,
    this.prefs,
    required this.ecom,
    required this.normal,
  });
  final SharedPreferences? prefs;
  final EcomState ecom;
  final NormalState normal;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '圖片壓縮',
      debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      home: HomeShell(prefs: prefs, ecom: ecom, normal: normal),
    );
  }
}

/// 左側切換普通 / 電商模式（窄螢幕改底部導覽列）。
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    this.prefs,
    required this.ecom,
    required this.normal,
  });
  final SharedPreferences? prefs;
  final EcomState ecom;
  final NormalState normal;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _kMode = 'app.mode';
  late int _index = widget.prefs?.getInt(_kMode) ?? 0;

  void _go(int i) {
    setState(() => _index = i);
    widget.prefs?.setInt(_kMode, i);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      NormalPage(state: widget.normal),
      EcommercePage(state: widget.ecom),
    ];
    final body = IndexedStack(index: _index, children: pages);
    return LayoutBuilder(
      builder: (context, c) => _layout(body, c.maxWidth < 720),
    );
  }

  Widget _layout(Widget body, bool narrow) {
    if (narrow) {
      return Scaffold(
        body: SafeArea(child: body),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _go,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.photo_size_select_large_outlined),
              label: '普通',
            ),
            NavigationDestination(
              icon: Icon(Icons.storefront_outlined),
              label: '電商',
            ),
          ],
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: _go,
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.photo_size_select_large_outlined),
                  label: Text('普通'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.storefront_outlined),
                  label: Text('電商'),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}
