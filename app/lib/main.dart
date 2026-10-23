import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ecommerce/page.dart';
import 'ecommerce/state.dart';
import 'l10n/l10n.dart';
import 'normal/page.dart';
import 'normal/state.dart';
import 'platform/android_files.dart';
import 'src/rust/api/ecommerce.dart' show ImgCategory;
import 'settings/app_settings.dart';
import 'settings/page.dart';
import 'settings/theme.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final prefs = await SharedPreferences.getInstance();
  final systemColor = await _systemColor();
  runApp(
    ImageCompressorApp(
      prefs: prefs,
      systemColor: systemColor,
      settings: AppSettings(prefs: prefs),
      ecom: EcomState(prefs: prefs),
      normal: NormalState(prefs: prefs),
    ),
  );
}

/// 系統色彩：Android 12+ 的桌布主色，或 Windows / macOS / Linux 的強調色；不支援時為 null。
Future<Color?> _systemColor() async {
  try {
    // ignore: deprecated_member_use
    final p = await DynamicColorPlugin.getCorePalette();
    if (p != null) return Color(p.primary.get(40));
  } catch (_) {}
  try {
    return await DynamicColorPlugin.getAccentColor();
  } catch (_) {
    return null;
  }
}

/// 舊版相容：以預設設定建立主題（測試用）。
ThemeData appTheme(Brightness b) =>
    buildTheme(brightness: b, settings: AppSettings());

class ImageCompressorApp extends StatelessWidget {
  const ImageCompressorApp({
    super.key,
    this.prefs,
    this.settings,
    this.systemColor,
    required this.ecom,
    required this.normal,
  });

  final SharedPreferences? prefs;

  /// 系統色彩（null = 此平台不支援跟隨系統）
  final Color? systemColor;
  final AppSettings? settings;
  final EcomState ecom;
  final NormalState normal;

  @override
  Widget build(BuildContext context) {
    final settings = this.settings ?? AppSettings(prefs: prefs);
    final systemColorAvailable = systemColor != null;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final useSystem = settings.useSystemColor && systemColorAvailable;
        ColorScheme? scheme(Brightness b) => useSystem
            ? ColorScheme.fromSeed(seedColor: systemColor!, brightness: b)
            : null;
        return MaterialApp(
          onGenerateTitle: (context) => context.l.appTitle,
          debugShowCheckedModeBanner: false,
          locale: settings.language.locale,
          supportedLocales: [for (final l in AppLanguage.values) l.locale],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          themeMode: settings.themeMode,
          theme: buildTheme(
            brightness: Brightness.light,
            settings: settings,
            dynamicScheme: scheme(Brightness.light),
          ),
          darkTheme: buildTheme(
            brightness: Brightness.dark,
            settings: settings,
            dynamicScheme: scheme(Brightness.dark),
          ),
          home: HomeShell(
            prefs: prefs,
            settings: settings,
            systemColorAvailable: systemColorAvailable,
            ecom: ecom,
            normal: normal,
          ),
        );
      },
    );
  }
}

/// 左側切換普通 / 電商 / 設定（窄螢幕改底部導覽列）。
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    this.prefs,
    required this.settings,
    this.systemColorAvailable = false,
    required this.ecom,
    required this.normal,
  });
  final SharedPreferences? prefs;
  final AppSettings settings;
  final bool systemColorAvailable;
  final EcomState ecom;
  final NormalState normal;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _kMode = 'app.mode';
  late int _index = (widget.prefs?.getInt(_kMode) ?? 0).clamp(0, 1);
  StreamSubscription<List<ImportedFile>>? _shareSub;

  @override
  void initState() {
    super.initState();
    if (AndroidFiles.supported) {
      _shareSub = AndroidFiles.instance.shared.listen(_onShared);
      AndroidFiles.instance.init();
    }
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  /// 從其他 App 分享進來：電商模式時詢問放到哪一區，其他情況加入普通模式。
  Future<void> _onShared(List<ImportedFile> files) async {
    if (!mounted || files.isEmpty) return;
    if (_index == 1 && !widget.ecom.running) {
      final l = context.l;
      final cat = await showDialog<ImgCategory>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(l.sharedToWhich(files.length)),
          children: [
            for (final c in ImgCategory.values)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, c),
                child: Text(categoryLabel(l, c)),
              ),
          ],
        ),
      );
      if (cat != null) await widget.ecom.addImported(cat, files);
      return;
    }
    if (widget.normal.running) return;
    _go(0);
    await widget.normal.addImported(files);
  }

  void _go(int i) {
    setState(() => _index = i);
    // 只記住普通 / 電商模式，設定頁不記
    if (i < 2) widget.prefs?.setInt(_kMode, i);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      NormalPage(state: widget.normal),
      EcommercePage(state: widget.ecom),
      SettingsPage(
        settings: widget.settings,
        systemColorAvailable: widget.systemColorAvailable,
      ),
    ];
    final body = IndexedStack(index: _index, children: pages);
    return LayoutBuilder(
      builder: (context, c) => _layout(context, body, c.maxWidth < 720),
    );
  }

  Widget _layout(BuildContext context, Widget body, bool narrow) {
    final l = context.l;
    final items = [
      (Icons.photo_size_select_large_outlined, l.navNormal),
      (Icons.storefront_outlined, l.navEcommerce),
      (Icons.settings_outlined, l.navSettings),
    ];
    if (narrow) {
      return Scaffold(
        body: SafeArea(child: body),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _go,
          destinations: [
            // tooltip 設為空字串：Flutter 的 Tooltip 在 Windows 無障礙橋接會崩潰（flutter/flutter#182444）
            for (final (icon, label) in items)
              NavigationDestination(
                icon: Icon(icon),
                label: label,
                tooltip: '',
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
              destinations: [
                for (final (icon, label) in items)
                  NavigationRailDestination(
                    icon: Icon(icon),
                    label: Text(label),
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
