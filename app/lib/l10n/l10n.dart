import 'dart:io';

import 'package:flutter/widgets.dart';

import '../platform/android_files.dart' show galleryDeniedCode;
import '../src/rust/api/common.dart';
import '../src/rust/api/ecommerce.dart';
import 'app_localizations.dart';

export 'app_localizations.dart';

extension L10nX on BuildContext {
  AppLocalizations get l => AppLocalizations.of(this);
}

/// 依介面語言格式化檔案大小（十進位：1 KB = 1000 bytes，與平台規格一致）。
String formatBytes(num b) {
  if (b >= 1000 * 1000) return '${(b / 1000 / 1000).toStringAsFixed(2)} MB';
  if (b >= 1000) return '${(b / 1000).toStringAsFixed(0)} KB';
  return '$b B';
}

String categoryLabel(AppLocalizations l, ImgCategory c) => switch (c) {
  ImgCategory.main => l.catMain,
  ImgCategory.variant => l.catVariant,
  ImgCategory.desc => l.catDesc,
};

String platformLabel(ShopPlatform p) => switch (p) {
  ShopPlatform.shopee => 'Shopee',
  ShopPlatform.momo => 'momo',
};

String errorKindText(AppLocalizations l, ErrorKind k) => switch (k) {
  ErrorKind.io => l.errIo,
  ErrorKind.decode => l.errDecode,
  ErrorKind.encode => l.errEncode,
  ErrorKind.invalid => l.errInvalid,
  ErrorKind.trash => l.errTrash,
  ErrorKind.unsupported => heifUnsupportedText(l),
  ErrorKind.other => l.errOther,
};

/// 此平台無法讀取 HEIC 時的說明（含安裝建議）。
String heifUnsupportedText(AppLocalizations l) {
  if (Platform.isWindows) return l.errHeifWindows;
  if (Platform.isLinux) return l.errHeifLinux;
  if (Platform.isAndroid) return l.errHeifAndroid;
  return l.errHeifOther;
}

String errorText(AppLocalizations l, AppError? e) {
  if (e == null) return l.unknownError;
  if (e.kind == ErrorKind.unsupported) return heifUnsupportedText(l);
  if (e.detail == galleryDeniedCode) return l.errGalleryDenied;
  final kind = errorKindText(l, e.kind);
  return e.detail.isEmpty ? kind : '$kind${l.colonSep}${e.detail}';
}

/// 把 Rust 端的結構化警告翻成目前語言。
String warningText(AppLocalizations l, WarningInfo w) {
  // FRB 的 i64 在不同平台可能是 int 或 BigInt
  int a(int i) {
    if (i >= w.args.length) return 0;
    final Object v = w.args[i];
    return v is BigInt ? v.toInt() : (v as num).toInt();
  }
  return switch (w.code) {
    'over_max' => l.warnOverMax(a(0), formatBytes(a(1)), formatBytes(a(2))),
    'downscaled' => l.warnDownscaled(a(0), a(1), a(2), a(3)),
    'under_min' => l.warnUnderMin(formatBytes(a(0)), formatBytes(a(1))),
    'gif_first_frame' => l.warnGifFirstFrame,
    'jpeg_reencoded' => l.warnJpegReencoded,
    'exif_thumbnail_removed' => l.warnExifThumbnailRemoved,
    'exif_dropped' => l.warnExifDropped,
    'target_not_reached' => l.warnTargetNotReached(
      formatBytes(a(0)),
      formatBytes(a(1)),
    ),
    _ => w.code,
  };
}
