import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../src/rust/api/files.dart';

/// 縮圖快取（LRU），由 Rust 產生，已套用 EXIF 方向與 sRGB。
class ThumbCache {
  ThumbCache._();
  static final instance = ThumbCache._();

  static const _maxEntries = 400;
  final _cache = <String, Future<Uint8List>>{}; // 插入順序 = LRU 順序

  Future<Uint8List> get(String path, {int maxSide = 320}) {
    final key = '$maxSide|$path';
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      return hit;
    }
    final f = thumbnail(path: path, maxSide: maxSide);
    _cache[key] = f;
    f.catchError((_) {
      _cache.remove(key);
      return Uint8List(0);
    });
    while (_cache.length > _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    return f;
  }

  void evict(String path) => _cache.removeWhere((k, _) => k.endsWith('|$path'));
}

class ImageThumb extends StatelessWidget {
  const ImageThumb({
    super.key,
    required this.path,
    this.size = 120,
    this.fit = BoxFit.contain,
  });

  final String path;
  final double size;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: FutureBuilder<Uint8List>(
        future: ThumbCache.instance.get(path),
        builder: (context, snap) {
          if (snap.hasError) {
            return Icon(Icons.broken_image_outlined, color: scheme.error);
          }
          if (!snap.hasData) {
            return const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          return Image.memory(snap.data!, fit: fit, gaplessPlayback: true);
        },
      ),
    );
  }
}
