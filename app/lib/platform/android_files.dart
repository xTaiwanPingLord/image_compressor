// Android 的檔案存取（MethodChannel "imgc/files"，實作在 FilesChannel.kt）。
//
// Rust 只吃一般路徑，所以選取 / 分享進來的圖片會先複製到 App 快取資料夾；
// 輸出先寫到快取，再透過 SAF 寫回使用者選的資料夾。

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// 使用者授權的資料夾（SAF tree）。
class TreeRef {
  const TreeRef(this.uri, this.name);
  final String uri;
  final String name;

  Map<String, String> toJson() => {'uri': uri, 'name': name};
  static TreeRef? fromJson(Object? j) => j is Map && j['uri'] is String
      ? TreeRef(j['uri'] as String, (j['name'] as String?) ?? '')
      : null;

  @override
  bool operator ==(Object other) => other is TreeRef && other.uri == uri;
  @override
  int get hashCode => uri.hashCode;
}

/// 來源資訊：圖片來自哪個資料夾（只有從資料夾加入的才有，可寫回原資料夾）。
class AndroidSource {
  const AndroidSource({
    required this.tree,
    required this.relDir,
    required this.name,
  });
  final TreeRef tree;

  /// 相對於 tree 根目錄的資料夾（'' = 根目錄）
  final String relDir;

  /// 原始檔名
  final String name;
}

/// 已複製到快取的圖片。
class ImportedFile {
  const ImportedFile(this.path, {this.source, this.base});
  final String path;
  final AndroidSource? source;

  /// 資料夾匯入時的本機鏡像根目錄（保留結構用）
  final String? base;
}

class AndroidFiles {
  AndroidFiles._() {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'shared') await _pullShared();
    });
  }
  static final instance = AndroidFiles._();

  static bool get supported => Platform.isAndroid;

  static const _ch = MethodChannel('imgc/files');
  final _shared = StreamController<List<ImportedFile>>.broadcast();

  /// 從其他 App 分享進來的圖片。
  Stream<List<ImportedFile>> get shared => _shared.stream;

  Future<void> _pullShared() async {
    final list = await _ch.invokeListMethod<Map>('takeShared');
    if (list == null || list.isEmpty) return;
    _shared.add([for (final m in list) ImportedFile(m['path'] as String)]);
  }

  /// 啟動時呼叫：取走冷啟動時分享進來的檔案。
  Future<void> init() => _pullShared();

  String? _cache;
  Future<String> cacheDir() async =>
      _cache ??= (await _ch.invokeMethod<String>('cacheDir'))!;

  /// 建立一個空的暫存輸出資料夾。
  Future<String> newExportDir() async {
    final d = Directory(
      p.join(
        await cacheDir(),
        'export',
        '${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await d.create(recursive: true);
    return d.path;
  }

  Future<List<ImportedFile>> pickImages() async {
    final list = await _ch.invokeListMethod<Map>('pickImages');
    return [
      for (final m in list ?? const []) ImportedFile(m['path'] as String),
    ];
  }

  Future<TreeRef?> pickFolder() async {
    final m = await _ch.invokeMapMethod<String, Object?>('pickFolder');
    if (m == null) return null;
    return TreeRef(m['uri'] as String, (m['name'] as String?) ?? '');
  }

  /// 確認先前授權的資料夾仍可用；回傳最新名稱（null = 已失去權限）。
  Future<String?> treeName(TreeRef t) async {
    try {
      return await _ch.invokeMethod<String>('treeName', {'tree': t.uri});
    } on PlatformException {
      return null;
    }
  }

  /// 把資料夾內的圖片複製到快取；recursive = 含子資料夾（略過 _old）。
  Future<List<ImportedFile>> importTree(
    TreeRef t, {
    bool recursive = false,
  }) async {
    final m = await _ch.invokeMapMethod<String, Object?>('importTree', {
      'tree': t.uri,
      'recursive': recursive,
    });
    if (m == null) return [];
    final tree = TreeRef(t.uri, (m['name'] as String?) ?? t.name);
    final base = m['base'] as String;
    return [
      for (final f in (m['files'] as List).cast<Map>())
        ImportedFile(
          f['path'] as String,
          base: base,
          source: AndroidSource(
            tree: tree,
            relDir: f['relDir'] as String,
            name: f['name'] as String,
          ),
        ),
    ];
  }

  /// 把 dir 中檔名符合 regex 的檔案移到 dir/_old；回傳數量。
  Future<int> moveToOld(TreeRef t, String dir, String regex) async =>
      await _ch.invokeMethod<int>('moveToOld', {
        'tree': t.uri,
        'dir': dir,
        'regex': regex,
      }) ??
      0;

  /// 把本機檔案寫到 tree 下的 relPath；backup = 已存在時先移到 _old。
  Future<void> writeFile(
    TreeRef t,
    String relPath,
    String src, {
    bool backup = false,
  }) => _ch.invokeMethod('writeFile', {
    'tree': t.uri,
    'relPath': relPath,
    'src': src,
    'backup': backup,
  });

  Future<bool> openTree(TreeRef t, [String dir = '']) async =>
      await _ch.invokeMethod<bool>('openTree', {'tree': t.uri, 'dir': dir}) ??
      false;
}

/// 輸出位置的字串表示（BatchSummary / 對話框用）：「tree uri」+「\n」+「相對資料夾」。
String encodeTreeDir(TreeRef t, String relDir) =>
    '${t.uri}\n${t.name}\n$relDir';

(TreeRef, String)? decodeTreeDir(String s) {
  final parts = s.split('\n');
  if (parts.length != 3 || !parts[0].startsWith('content://')) return null;
  return (TreeRef(parts[0], parts[1]), parts[2]);
}

/// 顯示用：「資料夾名/子資料夾」
String treeDirLabel(String s) {
  final d = decodeTreeDir(s);
  if (d == null) return s;
  return d.$2.isEmpty ? d.$1.name : '${d.$1.name}/${d.$2}';
}
