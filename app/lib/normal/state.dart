import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../src/rust/api/files.dart';
import '../src/rust/api/normal.dart';

/// 可變的設定（UI 綁定用），可轉成 Rust 的 NormalOptions 並存成 JSON。
class NormalSettings {
  NormalSettings.fromRust(NormalOptions o)
    : lossless = o.lossless,
      quality = o.quality,
      maxSize = o.maxSize.toInt(),
      jpegChroma = o.jpegChroma,
      pngLevel = o.pngLevel,
      keepMetadata = o.keepMetadata,
      keepDates = o.keepDates,
      resize = o.resize,
      resizeValue = o.resizeValue,
      resizeValue2 = o.resizeValue2,
      noEnlarge = o.noEnlarge,
      format = o.format,
      outputDir = o.outputDir,
      suffix = o.suffix,
      keepStructure = o.keepStructure,
      skipIfBigger = o.skipIfBigger;

  factory NormalSettings.defaults() =>
      NormalSettings.fromRust(defaultNormalOptions());

  bool lossless;
  int quality;

  /// 0 = 依品質；>0 = 目標大小（bytes）
  int maxSize;
  ChromaSubsampling jpegChroma;
  int pngLevel;
  bool keepMetadata;
  bool keepDates;
  ResizeMode resize;
  int resizeValue;
  int resizeValue2;
  bool noEnlarge;
  OutFormat format;
  String outputDir;
  String suffix;
  bool keepStructure;
  bool skipIfBigger;

  /// 目標大小模式
  bool get sizeMode => maxSize > 0;

  NormalOptions toRust() => NormalOptions(
    lossless: lossless,
    quality: quality,
    maxSize: BigInt.from(maxSize),
    jpegChroma: jpegChroma,
    pngLevel: pngLevel,
    keepMetadata: keepMetadata,
    keepDates: keepDates,
    resize: resize,
    resizeValue: resizeValue,
    resizeValue2: resizeValue2,
    noEnlarge: noEnlarge,
    format: format,
    outputDir: outputDir,
    suffix: suffix,
    keepStructure: keepStructure,
    skipIfBigger: skipIfBigger,
  );

  Map<String, Object> toJson() => {
    'lossless': lossless,
    'quality': quality,
    'maxSize': maxSize,
    'jpegChroma': jpegChroma.name,
    'pngLevel': pngLevel,
    'keepMetadata': keepMetadata,
    'keepDates': keepDates,
    'resize': resize.name,
    'resizeValue': resizeValue,
    'resizeValue2': resizeValue2,
    'noEnlarge': noEnlarge,
    'format': format.name,
    'outputDir': outputDir,
    'suffix': suffix,
    'keepStructure': keepStructure,
    'skipIfBigger': skipIfBigger,
  };

  void applyJson(Map<String, dynamic> j) {
    T pick<T>(String k, T fallback) => j[k] is T ? j[k] as T : fallback;
    E pickEnum<E extends Enum>(String k, List<E> values, E fallback) =>
        values.where((v) => v.name == j[k]).firstOrNull ?? fallback;
    lossless = pick('lossless', lossless);
    quality = pick('quality', quality).clamp(1, 100);
    maxSize = pick('maxSize', maxSize);
    jpegChroma = pickEnum('jpegChroma', ChromaSubsampling.values, jpegChroma);
    pngLevel = pick('pngLevel', pngLevel).clamp(0, 6);
    keepMetadata = pick('keepMetadata', keepMetadata);
    keepDates = pick('keepDates', keepDates);
    resize = pickEnum('resize', ResizeMode.values, resize);
    resizeValue = pick('resizeValue', resizeValue);
    resizeValue2 = pick('resizeValue2', resizeValue2);
    noEnlarge = pick('noEnlarge', noEnlarge);
    format = pickEnum('format', OutFormat.values, format);
    outputDir = pick('outputDir', outputDir);
    suffix = pick('suffix', suffix);
    keepStructure = pick('keepStructure', keepStructure);
    skipIfBigger = pick('skipIfBigger', skipIfBigger);
  }
}

enum ItemStatus { pending, working, done, keptOriginal, failed }

class NormalItem {
  NormalItem(this.path, this.base) : id = _next++;
  static int _next = 0;

  final int id;
  final String path;
  final String? base;
  int originalSize = 0;
  int width = 0;
  int height = 0;
  bool loaded = false;
  String? loadError;

  int? newSize;
  int? newWidth;
  int? newHeight;
  ItemStatus status = ItemStatus.pending;
  String? error;
  String? output;
  List<String> warnings = const [];

  String get name => p.basename(path);

  /// 節省比例（0–1；負值 = 變大）
  double? get saving =>
      newSize == null || originalSize == 0 ? null : 1 - newSize! / originalSize;
}

enum SortColumn { name, originalSize, newSize, resolution, saving, status }

/// 預覽狀態。
class PreviewState {
  PreviewState({this.itemId, this.loading = false, this.result, this.error});
  final int? itemId;
  final bool loading;
  final PreviewResult? result;
  final String? error;
}

class BatchSummary {
  BatchSummary(
    this.done,
    this.kept,
    this.failed,
    this.before,
    this.after,
    this.outputDirs,
  );
  final int done;
  final int kept;
  final int failed;
  final int before;
  final int after;
  final Set<String> outputDirs;
}

/// 普通模式狀態。
class NormalState extends ChangeNotifier {
  NormalState({SharedPreferences? prefs}) : _prefs = prefs {
    final raw = prefs?.getString(_kSettings);
    if (raw != null) {
      try {
        settings.applyJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
  }

  static const _kSettings = 'normal.settings';
  final SharedPreferences? _prefs;

  final NormalSettings settings = NormalSettings.defaults();
  final List<NormalItem> items = [];
  final Set<int> selected = {};
  int? focusedId;

  SortColumn? sortColumn;
  bool ascending = true;

  bool running = false;
  int doneCount = 0;
  int runTotal = 0;
  BatchSummary? lastSummary;

  PreviewState preview = PreviewState();

  NormalItem? get focused => items.where((i) => i.id == focusedId).firstOrNull;

  // ---------- 設定 ----------

  /// 修改設定後呼叫：存檔並重新產生預覽。
  void settingsChanged() {
    _prefs?.setString(_kSettings, jsonEncode(settings.toJson()));
    notifyListeners();
    refreshPreview();
  }

  void resetSettings() {
    settings.applyJson(NormalSettings.defaults().toJson());
    settingsChanged();
  }

  // ---------- 清單 ----------

  Future<void> addPaths(List<String> paths) async {
    final inputs = await collectImagesRecursive(paths: paths);
    final existing = items.map((i) => i.path).toSet();
    final added = <NormalItem>[];
    for (final inp in inputs) {
      if (existing.add(inp.path)) added.add(NormalItem(inp.path, inp.base));
    }
    if (added.isEmpty) return;
    items.addAll(added);
    _applySort();
    if (focusedId == null) select(added.first.id);
    notifyListeners();
    // 讀取尺寸（限制同時數量）
    const batch = 8;
    for (var i = 0; i < added.length; i += batch) {
      await Future.wait(added.skip(i).take(batch).map(_loadMeta));
      notifyListeners();
    }
  }

  Future<void> _loadMeta(NormalItem it) async {
    final m = await imageMeta(path: it.path);
    it
      ..originalSize = m.fileSize.toInt()
      ..width = m.width
      ..height = m.height
      ..loadError = m.error
      ..loaded = true;
  }

  void select(int id, {bool toggle = false, bool range = false}) {
    if (range && focusedId != null) {
      final a = items.indexWhere((i) => i.id == focusedId);
      final b = items.indexWhere((i) => i.id == id);
      if (a >= 0 && b >= 0) {
        final (lo, hi) = a < b ? (a, b) : (b, a);
        selected.addAll(items.sublist(lo, hi + 1).map((i) => i.id));
      }
    } else if (toggle) {
      selected.contains(id) ? selected.remove(id) : selected.add(id);
    } else {
      selected
        ..clear()
        ..add(id);
    }
    final changed = focusedId != id;
    focusedId = id;
    notifyListeners();
    if (changed) refreshPreview();
  }

  void selectAll() {
    selected
      ..clear()
      ..addAll(items.map((i) => i.id));
    notifyListeners();
  }

  void removeSelected() {
    items.removeWhere((i) => selected.contains(i.id));
    selected.clear();
    if (focused == null) {
      focusedId = items.firstOrNull?.id;
      if (focusedId != null) selected.add(focusedId!);
      refreshPreview();
    }
    notifyListeners();
  }

  void clear() {
    items.clear();
    selected.clear();
    focusedId = null;
    preview = PreviewState();
    lastSummary = null;
    notifyListeners();
  }

  void sortBy(SortColumn c) {
    if (sortColumn == c) {
      ascending = !ascending;
    } else {
      sortColumn = c;
      ascending = true;
    }
    _applySort();
    notifyListeners();
  }

  void _applySort() {
    final c = sortColumn;
    if (c == null) return;
    int cmp(NormalItem a, NormalItem b) => switch (c) {
      SortColumn.name => naturalCompare(a: a.name, b: b.name),
      SortColumn.originalSize => a.originalSize.compareTo(b.originalSize),
      SortColumn.newSize => (a.newSize ?? -1).compareTo(b.newSize ?? -1),
      SortColumn.resolution => (a.width * a.height).compareTo(
        b.width * b.height,
      ),
      SortColumn.saving => (a.saving ?? -9).compareTo(b.saving ?? -9),
      SortColumn.status => a.status.index.compareTo(b.status.index),
    };
    items.sort((a, b) => ascending ? cmp(a, b) : cmp(b, a));
  }

  // ---------- 預覽 ----------

  int _previewGen = 0;
  bool _previewBusy = false;
  bool _previewPending = false;

  /// 重新產生目前選取項目的預覽；執行中只保留最新一次請求。
  void refreshPreview() {
    final it = focused;
    if (it == null) {
      preview = PreviewState();
      notifyListeners();
      return;
    }
    _previewGen++;
    preview = PreviewState(
      itemId: it.id,
      loading: true,
      result: preview.itemId == it.id ? preview.result : null,
    );
    notifyListeners();
    if (_previewBusy) {
      _previewPending = true;
      return;
    }
    _runPreview();
  }

  Future<void> _runPreview() async {
    final it = focused;
    if (it == null) return;
    _previewBusy = true;
    final gen = _previewGen;
    PreviewState next;
    try {
      final r = await previewCompress(
        path: it.path,
        options: settings.toRust(),
      );
      next = PreviewState(itemId: it.id, result: r);
    } catch (e) {
      next = PreviewState(itemId: it.id, error: e.toString());
    }
    _previewBusy = false;
    if (gen == _previewGen) {
      preview = next;
      notifyListeners();
    }
    if (_previewPending) {
      _previewPending = false;
      _runPreview();
    }
  }

  // ---------- 批次 ----------

  String? get blockReason {
    if (running) return '執行中';
    if (items.isEmpty) return '請先加入圖片';
    return null;
  }

  /// 會覆寫原檔（同資料夾、無後綴）
  bool get overwritesOriginal =>
      settings.outputDir.trim().isEmpty && settings.suffix.isEmpty;

  Future<BatchSummary> run({bool onlySelected = false}) async {
    final targets = items
        .where((i) => !onlySelected || selected.contains(i.id))
        .toList();
    running = true;
    doneCount = 0;
    runTotal = targets.length;
    for (final t in targets) {
      t
        ..status = ItemStatus.working
        ..newSize = null
        ..error = null
        ..warnings = const [];
    }
    notifyListeners();
    final dirs = <String>{};
    try {
      await for (final r in runNormal(
        inputs: targets
            .map((t) => NormalInput(path: t.path, base: t.base))
            .toList(),
        options: settings.toRust(),
      )) {
        final t = targets[r.index];
        t
          ..status = switch (r.status) {
            FileStatus.done => ItemStatus.done,
            FileStatus.keptOriginal => ItemStatus.keptOriginal,
            FileStatus.failed => ItemStatus.failed,
          }
          ..error = r.error
          ..warnings = r.warnings
          ..output = r.output
          ..newSize = r.status == FileStatus.failed ? null : r.newSize.toInt()
          ..newWidth = r.width
          ..newHeight = r.height;
        if (r.originalSize > BigInt.zero) {
          t.originalSize = r.originalSize.toInt();
        }
        if (r.output != null) dirs.add(p.dirname(r.output!));
        doneCount++;
        notifyListeners();
      }
    } catch (e) {
      for (final t in targets.where((t) => t.status == ItemStatus.working)) {
        t
          ..status = ItemStatus.failed
          ..error = e.toString();
      }
    }
    running = false;
    final ok = targets.where(
      (t) => t.status == ItemStatus.done || t.status == ItemStatus.keptOriginal,
    );
    lastSummary = BatchSummary(
      targets.where((t) => t.status == ItemStatus.done).length,
      targets.where((t) => t.status == ItemStatus.keptOriginal).length,
      targets.where((t) => t.status == ItemStatus.failed).length,
      ok.fold(0, (a, t) => a + t.originalSize),
      ok.fold(0, (a, t) => a + (t.newSize ?? 0)),
      dirs,
    );
    _applySort();
    notifyListeners();
    return lastSummary!;
  }
}
