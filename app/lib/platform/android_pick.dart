import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'android_files.dart';

/// Android：先選來源（相簿 / 檔案），再開對應的挑選器。
Future<List<ImportedFile>> pickAndroidImages(BuildContext context) async {
  final l = context.l;
  final gallery = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(l.pickFromGallery),
            onTap: () => Navigator.pop(context, true),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: Text(l.pickFromFiles),
            onTap: () => Navigator.pop(context, false),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (gallery == null) return const [];
  return AndroidFiles.instance.pickImages(gallery: gallery);
}
