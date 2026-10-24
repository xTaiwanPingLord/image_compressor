// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/android_files.dart';
import '../src/rust/api/common.dart';
import '../src/rust/api/ecommerce.dart';
import '../src/rust/api/files.dart';

/// 清單中的一張圖。
class EcomItem {
  EcomItem(this.path, {this.source}) : id = _nextId++;

  static int _nextId = 0;

  final int id;
  final String path;

  /// Android：來自哪個授權資料夾（從資料夾加入才有）
  final AndroidSource? source;
  int width = 0;
  int height = 0;
  int fileSize = 0;
  AppError? error;
  bool loaded = false;
  Fit fit = Fit.pad;

  String get name => source?.name ?? p.basename(path);
}

enum RunPhase { idle, running }

/// 不能執行的原因。
enum EcomBlock {
  running,
  noName,
  badName,
  noPlatform,
  noImages,
  loading,
  unreadable,

  /// Android：沒有可寫入的輸出資料夾
  noOutputFolder,
}

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
  static const _kMaxQuality = 'ecom.maxQuality';
  static const _kChroma444 = 'ecom.chroma444';
  static const _kPlatforms = 'ecom.platforms';
  static const _kDefaultFit = 'ecom.defaultFit';
  static const _kAndroidOut = 'ecom.androidOut';

  /// Android：使用者指定的輸出資料夾（圖片不是從資料夾加入時使用）
  TreeRef? androidOut;

  /// Android：實際輸出的資料夾 = 圖片最多的來源資料夾，否則為指定的輸出資料夾。
  TreeRef? get androidTarget {
    final count = <TreeRef, int>{};
    for (final it in sections.values.expand((l) => l)) {
      final t = it.source?.tree;
      if (t != null) count[t] = (count[t] ?? 0) + 1;
    }
    if (count.isEmpty) return androidOut;
    return count.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  void setAndroidOut(TreeRef? t) {
    androidOut = t;
    final s = _prefs;
    if (s != null) {
      t == null
          ? s.remove(_kAndroidOut)
          : s.setString(_kAndroidOut, jsonEncode(t.toJson()));
    }
    notifyListeners();
  }

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
      maxQuality: (s.getInt(_kMaxQuality) ?? d.maxQuality).clamp(60, 100),
      chroma444: s.getBool(_kChroma444) ?? d.chroma444,
    );
    final pf = s.getStringList(_kPlatforms);
    if (pf != null) {
      platforms
        ..clear()
        ..addAll(ShopPlatform.values.where((x) => pf.contains(x.name)));
    }
    defaultFit = s.getString(_kDefaultFit) == 'crop' ? Fit.crop : Fit.pad;
    try {
      final raw = s.getString(_kAndroidOut);
      if (raw != null) androidOut = TreeRef.fromJson(jsonDecode(raw));
    } catch (_) {}
  }

  void _savePrefs() {
    final s = _prefs;
    if (s == null) return;
    s.setInt(_kShopeeMax, settings.shopeeMaxDesc);
    s.setInt(_kMomoMax, settings.momoMaxDesc);
    s.setBool(_kSmart, settings.smartCut);
    s.setInt(_kShopeeWidth, settings.shopeeMaxWidth);
    s.setInt(_kMomoMinLast, settings.momoMinLast);
    s.setInt(_kMaxQuality, settings.maxQuality);
    s.setBool(_kChroma444, settings.chroma444);
    s.setStringList(_kPlatforms, platforms.map((x) => x.name).toList());
    s.setString(_kDefaultFit, defaultFit.name);
  }

  void updateSettings(EcomSettings v, Fit fit) {
    settings = v;
    defaultFit = fit;
    _savePrefs();
    notifyListeners();
  }

  void setPlatforms(Set<ShopPlatform> v) {
    platforms
      ..clear()
      ..addAll(v);
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

  /// Android：加入已複製到快取的圖片（資料夾匯入時保留來源資訊）。
  Future<void> addImported(
    ImgCategory cat,
    List<ImportedFile> files, {
    int? index,
  }) async {
    if (files.isEmpty) return;
    final sorted = sortNatural(paths: [for (final f in files) f.path]);
    final byPath = {for (final f in files) f.path: f};
    final items = [
      for (final path in sorted)
        EcomItem(path, source: byPath[path]!.source)..fit = defaultFit,
    ];
    final list = sections[cat]!;
    final at = (index ?? list.length).clamp(0, list.length);
    list.insertAll(at, items);
    if (name.trim().isEmpty) name = guessName(items.first.name);
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

  /// 不能執行的原因；可執行時回傳 null（UI 負責翻譯）。
  EcomBlock? get blockReason {
    if (running) return EcomBlock.running;
    if (name.trim().isEmpty) return EcomBlock.noName;
    if (RegExp(r'[\\/:*?"<>|]').hasMatch(name)) return EcomBlock.badName;
    if (platforms.isEmpty) return EcomBlock.noPlatform;
    if (totalCount == 0) return EcomBlock.noImages;
    if (!allLoaded) return EcomBlock.loading;
    if (hasErrors) return EcomBlock.unreadable;
    if (AndroidFiles.supported && androidTarget == null) {
      return EcomBlock.noOutputFolder;
    }
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
    outputRoot: null,
  );

  /// 執行；回傳最後一個進度（Done 或 Failed）。
  Future<EcomProgress> run({bool dryRun = false}) async {
    phase = RunPhase.running;
    progress = null;
    notifyListeners();
    EcomProgress? last;
    try {
      final android = AndroidFiles.supported;
      final target = androidTarget;
      var job = buildJob();
      String? staging;
      if (android) {
        staging = await AndroidFiles.instance.newExportDir();
        job = EcomJob(
          name: job.name,
          main: job.main,
          variant: job.variant,
          desc: job.desc,
          platforms: job.platforms,
          settings: job.settings,
          outputRoot: staging,
        );
      }
      await for (final ev in runEcommerce(job: job, dryRun: dryRun)) {
        last = ev;
        progress = ev;
        notifyListeners();
      }
      final r = last?.report;
      if (android &&
          !dryRun &&
          last?.stage == EcomStage.done &&
          r != null &&
          r.overflow.isEmpty &&
          target != null) {
        last = EcomProgress(
          stage: EcomStage.done,
          done: last!.done,
          total: last.total,
          report: await _exportAndroid(job.name, r, staging!, target),
        );
        progress = last;
      }
    } catch (e) {
      last = EcomProgress(
        stage: EcomStage.failed,
        done: 0,
        total: 0,
        error: AppError(
          kind: e is PlatformException ? ErrorKind.io : ErrorKind.other,
          detail: e is PlatformException ? (e.message ?? e.code) : e.toString(),
        ),
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
          error: AppError(kind: ErrorKind.other, detail: ''),
        );
  }

  /// Android：把暫存輸出寫回使用者資料夾（先把同類別的舊檔移到 _old/）。
  Future<EcomReport> _exportAndroid(
    String name,
    EcomReport r,
    String staging,
    TreeRef tree,
  ) async {
    final af = AndroidFiles.instance;
    var disposed = 0;
    final pfs = r.outputs.map((o) => o.platform).toSet().toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    for (final pf in pfs) {
      final outs = r.outputs.where((o) => o.platform == pf).toList();
      final dir = pf.name; // shopee / momo
      final cats = outs.map((o) => _catPrefix(o.category)).toSet().join('|');
      disposed += await af.moveToOld(
        tree,
        dir,
        '^${RegExp.escape(name)}_($cats)_\\d+\\.jpg\$',
      );
      for (final o in outs) {
        await af.writeFile(
          tree,
          '$dir/${o.fileName}',
          p.join(staging, dir, o.fileName),
        );
      }
    }
    return EcomReport(
      outputRoot: encodeTreeDir(tree, ''),
      descCounts: r.descCounts,
      overflow: r.overflow,
      outputs: r.outputs,
      writtenCount: r.writtenCount,
      disposedCount: disposed,
    );
  }

  static String _catPrefix(ImgCategory c) => switch (c) {
    ImgCategory.main => 'main',
    ImgCategory.variant => 'variant',
    ImgCategory.desc => 'desc',
  };
}
