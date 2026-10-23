// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../src/rust/api/ecommerce.dart';
import '../src/rust/api/files.dart';

/// 清單中的一張圖。
class EcomItem {
  EcomItem(this.path) : id = _nextId++;

  static int _nextId = 0;

  final int id;
  final String path;
  int width = 0;
  int height = 0;
  int fileSize = 0;
  String? error;
  bool loaded = false;
  Fit fit = Fit.pad;

  String get name => p.basename(path);
}

enum RunPhase { idle, running }

/// 電商模式狀態。
class EcomState extends ChangeNotifier {
  EcomState({SharedPreferences? prefs}) : _prefs = prefs {
    _loadPrefs();
  }

  final SharedPreferences? _prefs;

  final Map<ImgCategory, List<EcomItem>> sections = {
    ImgCategory.main: [],
    ImgCategory.variant: [],
    ImgCategory.desc: [],
  };

  String name = '';
  final Set<ShopPlatform> platforms = {ShopPlatform.shopee, ShopPlatform.momo};
  EcomSettings settings = defaultSettings();
  Fit defaultFit = Fit.pad;

  RunPhase phase = RunPhase.idle;
  EcomProgress? progress;

  bool get running => phase == RunPhase.running;
  int get totalCount => sections.values.fold(0, (a, l) => a + l.length);
  bool get hasErrors =>
      sections.values.any((l) => l.any((i) => i.error != null));
  bool get allLoaded => sections.values.every((l) => l.every((i) => i.loaded));

  // ---------- 偏好設定 ----------

  static const _kShopeeMax = 'ecom.shopeeMaxDesc';
  static const _kMomoMax = 'ecom.momoMaxDesc';
  static const _kSmart = 'ecom.smartCut';
  static const _kShopeeWidth = 'ecom.shopeeMaxWidth';
  static const _kMomoMinLast = 'ecom.momoMinLast';
  static const _kPlatforms = 'ecom.platforms';
  static const _kDefaultFit = 'ecom.defaultFit';

  void _loadPrefs() {
    final s = _prefs;
    if (s == null) return;
    final d = defaultSettings();
    settings = EcomSettings(
      shopeeMaxDesc: s.getInt(_kShopeeMax) ?? d.shopeeMaxDesc,
      momoMaxDesc: s.getInt(_kMomoMax) ?? d.momoMaxDesc,
      smartCut: s.getBool(_kSmart) ?? d.smartCut,
      shopeeMaxWidth: s.getInt(_kShopeeWidth) ?? d.shopeeMaxWidth,
      momoMinLast: s.getInt(_kMomoMinLast) ?? d.momoMinLast,
    );
    final pf = s.getStringList(_kPlatforms);
    if (pf != null) {
      platforms
        ..clear()
        ..addAll(ShopPlatform.values.where((x) => pf.contains(x.name)));
    }
    defaultFit = s.getString(_kDefaultFit) == 'crop' ? Fit.crop : Fit.pad;
  }

  void _savePrefs() {
    final s = _prefs;
    if (s == null) return;
    s.setInt(_kShopeeMax, settings.shopeeMaxDesc);
    s.setInt(_kMomoMax, settings.momoMaxDesc);
    s.setBool(_kSmart, settings.smartCut);
    s.setInt(_kShopeeWidth, settings.shopeeMaxWidth);
    s.setInt(_kMomoMinLast, settings.momoMinLast);
    s.setStringList(_kPlatforms, platforms.map((x) => x.name).toList());
    s.setString(_kDefaultFit, defaultFit.name);
  }

  void updateSettings(EcomSettings v, Fit fit) {
    settings = v;
    defaultFit = fit;
    _savePrefs();
    notifyListeners();
  }

  void togglePlatform(ShopPlatform pf, bool on) {
    on ? platforms.add(pf) : platforms.remove(pf);
    _savePrefs();
    notifyListeners();
  }

  void setName(String v) {
    name = v;
    notifyListeners();
  }

  // ---------- 清單操作 ----------

  /// 由檔名推測 name：去掉結尾的序號，例如 cooling_laird_7 → cooling_laird。
  static String guessName(String path) {
    final stem = p.basenameWithoutExtension(path);
    final g = stem.replaceFirst(RegExp(r'[\s_\-]*\(?\d+\)?$'), '');
    return g.isEmpty ? stem : g;
  }

  /// 加入檔案或資料夾（資料夾不遞迴）；新加入的這批依檔名自然排序。
  Future<void> addPaths(
    ImgCategory cat,
    List<String> paths, {
    int? index,
  }) async {
    final files = await collectImages(paths: paths);
    if (files.isEmpty) return;
    final list = sections[cat]!;
    final existing = sections.values
        .expand((l) => l)
        .map((i) => i.path)
        .toSet();
    final items = files
        .where((f) => !existing.contains(f))
        .map((f) => EcomItem(f)..fit = defaultFit)
        .toList();
    if (items.isEmpty) return;
    final at = (index ?? list.length).clamp(0, list.length);
    list.insertAll(at, items);
    if (name.trim().isEmpty) name = guessName(items.first.path);
    notifyListeners();
    await Future.wait(items.map(_loadMeta));
  }

  Future<void> _loadMeta(EcomItem it) async {
    final m = await imageMeta(path: it.path);
    it
      ..width = m.width
      ..height = m.height
      ..fileSize = m.fileSize.toInt()
      ..error = m.error
      ..loaded = true;
    notifyListeners();
  }

  ImgCategory? categoryOf(EcomItem it) {
    for (final e in sections.entries) {
      if (e.value.contains(it)) return e.key;
    }
    return null;
  }

  /// 移動到指定區塊的 index 之前（index 為 null = 放到最後）。
  void move(EcomItem it, ImgCategory to, {int? index}) {
    final from = categoryOf(it);
    if (from == null) return;
    final src = sections[from]!;
    final dst = sections[to]!;
    var at = index ?? dst.length;
    final old = src.indexOf(it);
    if (from == to && old < at) at -= 1;
    src.removeAt(old);
    dst.insert(at.clamp(0, dst.length), it);
    notifyListeners();
  }

  void remove(EcomItem it) {
    for (final l in sections.values) {
      l.remove(it);
    }
    notifyListeners();
  }

  void clear(ImgCategory cat) {
    sections[cat]!.clear();
    notifyListeners();
  }

  void clearAll() {
    for (final l in sections.values) {
      l.clear();
    }
    name = '';
    notifyListeners();
  }

  void setFit(EcomItem it, Fit f) {
    it.fit = f;
    notifyListeners();
  }

  /// 在目前勾選的平台下，此圖是否需要選擇補白/裁切。
  bool needsFit(EcomItem it, ImgCategory cat) {
    if (!it.loaded || it.error != null || cat == ImgCategory.desc) return false;
    return platforms.any(
      (pf) => needsFitChoice(
        platform: pf,
        category: cat,
        width: it.width,
        height: it.height,
      ),
    );
  }

  /// 不能執行的原因；可執行時回傳 null。
  String? get blockReason {
    if (running) return '執行中';
    if (name.trim().isEmpty) return '請輸入 name';
    if (RegExp(r'[\\/:*?"<>|]').hasMatch(name)) {
      return 'name 不能包含 \\ / : * ? " < > |';
    }
    if (platforms.isEmpty) return '請至少勾選一個平台';
    if (totalCount == 0) return '請先加入圖片';
    if (!allLoaded) return '讀取圖片資訊中';
    if (hasErrors) return '有無法讀取的圖片，請先移除';
    return null;
  }

  EcomJob buildJob() => EcomJob(
    name: name.trim(),
    main: sections[ImgCategory.main]!
        .map((i) => EcomInput(path: i.path, fit: i.fit))
        .toList(),
    variant: sections[ImgCategory.variant]!
        .map((i) => EcomInput(path: i.path, fit: i.fit))
        .toList(),
    desc: sections[ImgCategory.desc]!.map((i) => i.path).toList(),
    platforms: ShopPlatform.values.where(platforms.contains).toList(),
    settings: settings,
  );

  /// 執行；回傳最後一個進度（Done 或 Failed）。
  Future<EcomProgress> run({bool dryRun = false}) async {
    phase = RunPhase.running;
    progress = null;
    notifyListeners();
    EcomProgress? last;
    try {
      await for (final ev in runEcommerce(job: buildJob(), dryRun: dryRun)) {
        last = ev;
        progress = ev;
        notifyListeners();
      }
    } catch (e) {
      last = EcomProgress(
        stage: EcomStage.failed,
        done: 0,
        total: 0,
        error: e.toString(),
      );
    } finally {
      phase = RunPhase.idle;
      notifyListeners();
    }
    return last ??
        const EcomProgress(
          stage: EcomStage.failed,
          done: 0,
          total: 0,
          error: '沒有收到結果',
        );
  }
}
