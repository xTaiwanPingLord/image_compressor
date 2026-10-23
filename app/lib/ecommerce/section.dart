import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../src/rust/api/ecommerce.dart';
import '../widgets/thumb.dart';
import 'state.dart';
import '../widgets/hint.dart';

XTypeGroup imageTypeGroup(AppLocalizations l) => XTypeGroup(
  label: l.imagesTypeLabel,
  extensions: const ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'tif', 'tiff', 'gif'],
);

/// 一個區塊：標題列 + 格狀縮圖；可拖放檔案、拖曳排序、跨區移動。
class EcomSection extends StatefulWidget {
  const EcomSection({
    super.key,
    required this.state,
    required this.category,
    this.expand = false,
  });

  final EcomState state;
  final ImgCategory category;

  /// 填滿可用高度（窄螢幕分頁時使用）
  final bool expand;

  @override
  State<EcomSection> createState() => _EcomSectionState();
}

class _EcomSectionState extends State<EcomSection> {
  bool _fileHover = false;
  bool _itemHover = false;

  EcomState get s => widget.state;
  List<EcomItem> get items => s.sections[widget.category]!;

  Future<void> _pickFiles() async {
    final files = await openFiles(
      acceptedTypeGroups: [imageTypeGroup(context.l)],
    );
    if (files.isEmpty) return;
    await s.addPaths(widget.category, files.map((f) => f.path).toList());
  }

  Future<void> _pickFolder() async {
    final dir = await getDirectoryPath();
    if (dir == null) return;
    await s.addPaths(widget.category, [dir]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final highlight = _fileHover || _itemHover;

    final grid = items.isEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Text(
                context.l.dropHere,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        : Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < items.length; i++)
                _ItemTile(
                  key: ValueKey(items[i].id),
                  state: s,
                  item: items[i],
                  category: widget.category,
                  index: i,
                ),
            ],
          );

    final body = DragTarget<EcomItem>(
      onWillAcceptWithDetails: (_) {
        if (!s.running) setState(() => _itemHover = true);
        return !s.running;
      },
      onLeave: (_) => setState(() => _itemHover = false),
      onAcceptWithDetails: (d) {
        setState(() => _itemHover = false);
        s.move(d.data, widget.category);
      },
      builder: (context, _, _) => DropTarget(
        enable: !s.running,
        onDragEntered: (_) => setState(() => _fileHover = true),
        onDragExited: (_) => setState(() => _fileHover = false),
        onDragDone: (d) {
          setState(() => _fileHover = false);
          s.addPaths(widget.category, d.files.map((f) => f.path).toList());
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 120),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: highlight
                ? scheme.primaryContainer.withValues(alpha: 0.35)
                : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: highlight ? scheme.primary : scheme.outlineVariant,
              width: highlight ? 2 : 1,
            ),
          ),
          child: grid,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Text(
                categoryLabel(context.l, widget.category),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(width: 8),
              Text(
                context.l.imageCount(items.length),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Hint(
                message: context.l.addImages,
                child: IconButton(
                  onPressed: s.running ? null : _pickFiles,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                ),
              ),
              Hint(
                message: context.l.addFolder,
                child: IconButton(
                  onPressed: s.running ? null : _pickFolder,
                  icon: const Icon(Icons.create_new_folder_outlined),
                ),
              ),
              Hint(
                message: context.l.clearSection,
                child: IconButton(
                  onPressed: s.running || items.isEmpty
                      ? null
                      : () => s.clear(widget.category),
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
              ),
            ],
          ),
        ),
        if (widget.expand)
          Expanded(child: SingleChildScrollView(child: body))
        else
          body,
      ],
    );
  }
}

class _ItemTile extends StatefulWidget {
  const _ItemTile({
    super.key,
    required this.state,
    required this.item,
    required this.category,
    required this.index,
  });

  final EcomState state;
  final EcomItem item;
  final ImgCategory category;
  final int index;

  @override
  State<_ItemTile> createState() => _ItemTileState();
}

class _ItemTileState extends State<_ItemTile> {
  bool _insertHover = false;

  static const double tileWidth = 140;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final it = widget.item;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final small = theme.textTheme.bodySmall;
    final showFit = s.needsFit(it, widget.category);

    final card = Container(
      width: tileWidth,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: it.error != null ? scheme.error : scheme.outlineVariant,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              Container(
                height: 120,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: it.error != null
                    ? Icon(Icons.broken_image_outlined, color: scheme.error)
                    : ImageThumb(path: it.path, size: 120),
              ),
              Positioned(
                left: 4,
                top: 4,
                child: _Badge(text: '${widget.index + 1}'),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: Hint(
                  message: context.l.remove,
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      backgroundColor: scheme.surface.withValues(alpha: 0.85),
                    ),
                    onPressed: s.running ? null : () => s.remove(it),
                    icon: const Icon(Icons.close, size: 16),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Hint(
            message: it.path,
            child: Text(
              it.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: small,
            ),
          ),
          Text(
            it.error != null
                ? context.l.unreadable
                : it.loaded
                ? '${it.width}×${it.height}'
                : '…',
            style: small?.copyWith(
              color: it.error != null ? scheme.error : scheme.onSurfaceVariant,
            ),
          ),
          if (showFit) ...[
            const SizedBox(height: 4),
            SegmentedButton<Fit>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity(horizontal: -4, vertical: -4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: [
                ButtonSegment(value: Fit.pad, label: Text(context.l.pad)),
                ButtonSegment(value: Fit.crop, label: Text(context.l.crop)),
              ],
              selected: {it.fit},
              onSelectionChanged: s.running
                  ? null
                  : (v) => s.setFit(it, v.first),
            ),
          ],
        ],
      ),
    );

    // 拖到這張上 = 插入到它前面
    final target = DragTarget<EcomItem>(
      onWillAcceptWithDetails: (d) {
        final ok = !s.running && d.data != it;
        if (ok) setState(() => _insertHover = true);
        return ok;
      },
      onLeave: (_) => setState(() => _insertHover = false),
      onAcceptWithDetails: (d) {
        setState(() => _insertHover = false);
        s.move(d.data, widget.category, index: widget.index);
      },
      builder: (context, _, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: _insertHover ? 4 : 0,
            height: 150,
            margin: EdgeInsets.only(right: _insertHover ? 6 : 0),
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          card,
        ],
      ),
    );

    if (s.running) return target;
    return Draggable<EcomItem>(
      data: it,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.85,
          child: SizedBox(width: tileWidth, child: card),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: card),
      child: MouseRegion(cursor: SystemMouseCursors.grab, child: target),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.inverseSurface.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(color: scheme.onInverseSurface, fontSize: 11),
      ),
    );
  }
}
