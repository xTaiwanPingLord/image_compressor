import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ecommerce/dialogs.dart' show openFolder;
import '../ecommerce/section.dart' show imageTypeGroup;
import '../l10n/l10n.dart';
import '../src/rust/api/common.dart' show ErrorKind;
import '../platform/android_files.dart';
import '../platform/android_pick.dart';
import '../widgets/thumb.dart';
import 'settings_panel.dart';
import 'state.dart';
import '../widgets/hint.dart';

/// 普通模式頁面：左側清單＋下方預覽，右側設定。
class NormalPage extends StatefulWidget {
  const NormalPage({super.key, required this.state});
  final NormalState state;

  @override
  State<NormalPage> createState() => _NormalPageState();
}

class _NormalPageState extends State<NormalPage> {
  bool _hover = false;

  NormalState get s => widget.state;

  Future<void> _addFiles() async {
    if (AndroidFiles.supported) {
      await s.addImported(await pickAndroidImages(context));
      return;
    }
    final f = await openFiles(acceptedTypeGroups: [imageTypeGroup(context.l)]);
    if (f.isNotEmpty) await s.addPaths(f.map((x) => x.path).toList());
  }

  Future<void> _addFolder() async {
    if (AndroidFiles.supported) {
      final t = await AndroidFiles.instance.pickFolder();
      if (t == null) return;
      await s.addImported(
        await AndroidFiles.instance.importTree(t, recursive: true),
      );
      return;
    }
    final d = await getDirectoryPath();
    if (d != null) await s.addPaths([d]);
  }

  Future<void> _run({bool onlySelected = false}) async {
    if (s.overwritesOriginal) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded),
          title: Text(context.l.overwriteTitle),
          content: Text(
            AndroidFiles.supported
                ? context.l.overwriteBodyAndroid
                : context.l.overwriteBody,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l.continueAction),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    final sum = await s.run(onlySelected: onlySelected);
    if (!mounted) return;
    final l = context.l;
    final saved = sum.before - sum.after;
    final pct = sum.before == 0 ? 0 : saved / sum.before * 100;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        persist: false, // 有按鈕時預設不會自動消失
        content: Text(
          '${[l.normalDone(sum.done), if (sum.kept > 0) l.normalKept(sum.kept), if (sum.failed > 0) l.normalFailedCount(sum.failed)].join(l.listSep)}'
          ' · ${l.sizeChange(formatBytes(sum.before), formatBytes(sum.after), pct.toStringAsFixed(1))}',
        ),
        action: sum.outputDirs.isEmpty
            ? null
            : SnackBarAction(
                label: sum.outputDirs.first == galleryOutput
                    ? l.openGallery
                    : l.openFolder,
                onPressed: () => openFolder(sum.outputDirs.first),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 1000;
          final main = Column(
            children: [
              _toolbar(context, wide),
              const Divider(height: 1),
              Expanded(flex: 5, child: _dropArea(context)),
              const Divider(height: 1),
              Expanded(flex: 4, child: _PreviewPane(state: s)),
              _statusBar(context),
            ],
          );
          if (!wide) return main;
          return Row(
            children: [
              Expanded(child: main),
              const VerticalDivider(width: 1),
              SizedBox(width: 340, child: NormalSettingsPanel(state: s)),
            ],
          );
        },
      ),
    );
  }

  void _openSettingsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: NormalSettingsPanel(state: s),
      ),
    );
  }

  Widget _toolbar(BuildContext context, bool wide) {
    final off = s.running;
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: s.blockReason == null ? () => _run() : null,
            icon: const Icon(Icons.compress),
            label: Text(context.l.compressAll),
          ),
          OutlinedButton(
            onPressed: off || s.selected.isEmpty
                ? null
                : () => _run(onlySelected: true),
            child: Text(context.l.compressSelected(s.selected.length)),
          ),
          const SizedBox(width: 8),
          Hint(
            message: context.l.addImages,
            child: IconButton(
              onPressed: off ? null : _addFiles,
              icon: const Icon(Icons.add_photo_alternate_outlined),
            ),
          ),
          Hint(
            message: context.l.addFolderRecursive,
            child: IconButton(
              onPressed: off ? null : _addFolder,
              icon: const Icon(Icons.create_new_folder_outlined),
            ),
          ),
          const SizedBox(width: 8),
          Hint(
            message: context.l.clearAll,
            child: IconButton(
              onPressed: off || s.items.isEmpty ? null : s.clear,
              icon: const Icon(Icons.clear_all),
            ),
          ),
          Hint(
            message: context.l.removeSelected(s.selected.length),
            child: IconButton(
              onPressed: off || s.selected.isEmpty ? null : s.removeSelected,
              icon: const Icon(Icons.remove_circle_outline),
            ),
          ),
          if (!wide)
            Hint(
              message: context.l.settingsTooltip,
              child: IconButton(
                onPressed: _openSettingsSheet,
                icon: const Icon(Icons.tune),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dropArea(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DropTarget(
      enable: !s.running,
      onDragEntered: (_) => setState(() => _hover = true),
      onDragExited: (_) => setState(() => _hover = false),
      onDragDone: (d) {
        setState(() => _hover = false);
        s.addPaths(d.files.map((f) => f.path).toList());
      },
      child: Container(
        decoration: BoxDecoration(
          color: _hover ? scheme.primaryContainer.withValues(alpha: 0.3) : null,
          border: _hover ? Border.all(color: scheme.primary, width: 2) : null,
        ),
        child: s.items.isEmpty
            ? Center(
                child: Text(
                  context.l.dropHere,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              )
            : _FileTable(state: s),
      ),
    );
  }

  Widget _statusBar(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l;
    String text;
    Color? color;
    if (s.running) {
      text = l.ecomEncoding(s.doneCount, s.runTotal);
    } else if (s.blockReason == NormalBlock.needOutputFolder) {
      text = l.blockNeedOutputFolder;
      color = theme.colorScheme.error;
    } else {
      final total = s.items.fold<int>(0, (a, i) => a + i.originalSize);
      text = l.normalStatusIdle(s.items.length, formatBytes(total));
      final sum = s.lastSummary;
      if (sum != null && sum.before > 0) {
        final pct = (sum.before - sum.after) / sum.before * 100;
        text +=
            ' · ${l.normalStatusLast(l.sizeChange(formatBytes(sum.before), formatBytes(sum.after), pct.toStringAsFixed(1)))}';
      }
    }
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (s.running)
            LinearProgressIndicator(
              value: s.runTotal == 0 ? null : s.doneCount / s.runTotal,
              minHeight: 3,
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- 清單 ----------------

class _FileTable extends StatelessWidget {
  const _FileTable({required this.state});
  final NormalState state;

  static const _cols = [
    (SortColumn.name, 0, TextAlign.left),
    (SortColumn.originalSize, 90, TextAlign.right),
    (SortColumn.newSize, 90, TextAlign.right),
    (SortColumn.resolution, 170, TextAlign.right),
    (SortColumn.saving, 70, TextAlign.right),
    (SortColumn.status, 100, TextAlign.left),
  ];

  static String _colLabel(AppLocalizations l, SortColumn c) => switch (c) {
    SortColumn.name => l.colName,
    SortColumn.originalSize => l.colOriginalSize,
    SortColumn.newSize => l.colNewSize,
    SortColumn.resolution => l.colResolution,
    SortColumn.saving => l.colSaving,
    SortColumn.status => l.colStatus,
  };

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, c) => _build(context, c.maxWidth < 700));

  Widget _build(BuildContext context, bool compact) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = state;

    // 窄版：隱藏解析度欄並縮窄其他欄
    const compactWidths = [0, 76, 76, 0, 60, 72];
    final l = context.l;
    Widget cell(int i, Widget child) {
      if (compact && i == 3) return const SizedBox.shrink();
      final w = compact ? compactWidths[i] : _cols[i].$2;
      final pad = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: child,
      );
      return w == 0
          ? Expanded(child: pad)
          : SizedBox(width: w.toDouble(), child: pad);
    }

    final header = Container(
      color: scheme.surfaceContainerLow,
      height: 34,
      child: Row(
        children: [
          for (var i = 0; i < _cols.length; i++)
            cell(
              i,
              InkWell(
                onTap: () => s.sortBy(_cols[i].$1),
                child: Row(
                  mainAxisAlignment: _cols[i].$3 == TextAlign.right
                      ? MainAxisAlignment.end
                      : MainAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Text(
                        _colLabel(l, _cols[i].$1),
                        style: theme.textTheme.labelMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (s.sortColumn == _cols[i].$1)
                      Icon(
                        s.ascending ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 14,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );

    return Focus(
      autofocus: false,
      onKeyEvent: (node, ev) {
        if (ev is! KeyDownEvent) return KeyEventResult.ignored;
        final ctrl =
            HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed;
        if (ev.logicalKey == LogicalKeyboardKey.delete && !s.running) {
          s.removeSelected();
          return KeyEventResult.handled;
        }
        if (ctrl && ev.logicalKey == LogicalKeyboardKey.keyA) {
          s.selectAll();
          return KeyEventResult.handled;
        }
        final idx = s.items.indexWhere((i) => i.id == s.focusedId);
        if (ev.logicalKey == LogicalKeyboardKey.arrowDown &&
            idx < s.items.length - 1) {
          s.select(s.items[idx + 1].id);
          return KeyEventResult.handled;
        }
        if (ev.logicalKey == LogicalKeyboardKey.arrowUp && idx > 0) {
          s.select(s.items[idx - 1].id);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        children: [
          header,
          Expanded(
            child: ListView.builder(
              itemCount: s.items.length,
              itemExtent: 32,
              itemBuilder: (context, i) {
                final it = s.items[i];
                final sel = s.selected.contains(it.id);
                final small = theme.textTheme.bodySmall;
                final saving = it.saving;
                final (statusText, statusColor) = switch (it.status) {
                  ItemStatus.pending => (
                    it.loadError?.kind == ErrorKind.unsupported
                        ? l.heicUnsupportedShort
                        : it.loadError != null
                        ? l.unreadable
                        : '',
                    it.loadError != null ? scheme.error : null,
                  ),
                  ItemStatus.working => (l.statusWorking, scheme.primary),
                  ItemStatus.done => (l.statusDone, Colors.green.shade600),
                  ItemStatus.keptOriginal => (l.statusKept, scheme.tertiary),
                  ItemStatus.failed => (l.statusFailed, scheme.error),
                };
                final res =
                    it.newWidth != null &&
                        it.status == ItemStatus.done &&
                        (it.newWidth != it.width || it.newHeight != it.height)
                    ? '${it.width}×${it.height} → ${it.newWidth}×${it.newHeight}'
                    : it.loaded
                    ? '${it.width}×${it.height}'
                    : '';
                return Material(
                  color: sel
                      ? scheme.secondaryContainer
                      : (i.isOdd ? scheme.surfaceContainerLowest : null),
                  child: InkWell(
                    onTap: () {
                      final kb = HardwareKeyboard.instance;
                      Focus.maybeOf(context)?.requestFocus();
                      s.select(
                        it.id,
                        toggle: kb.isControlPressed || kb.isMetaPressed,
                        range: kb.isShiftPressed,
                      );
                    },
                    child: Row(
                      children: [
                        cell(
                          0,
                          Hint(
                            message: it.output ?? it.location,
                            waitDuration: const Duration(milliseconds: 600),
                            child: Text(
                              it.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        cell(
                          1,
                          Text(
                            it.loaded ? formatBytes(it.originalSize) : '',
                            style: small,
                            textAlign: TextAlign.right,
                          ),
                        ),
                        cell(
                          2,
                          Text(
                            it.newSize == null ? '' : formatBytes(it.newSize!),
                            style: small,
                            textAlign: TextAlign.right,
                          ),
                        ),
                        cell(
                          3,
                          Text(
                            res,
                            style: small,
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        cell(
                          4,
                          Text(
                            saving == null
                                ? ''
                                : '${(saving * 100).toStringAsFixed(1)}%',
                            style: small?.copyWith(
                              color: saving != null && saving < 0
                                  ? scheme.error
                                  : null,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        cell(
                          5,
                          Hint(
                            message: [
                              if (it.error != null) errorText(l, it.error),
                              if (it.loadError != null)
                                errorText(l, it.loadError),
                              for (final w in it.warnings) warningText(l, w),
                            ].join('\n'),
                            child: Text(
                              statusText,
                              style: small?.copyWith(color: statusColor),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- 預覽 ----------------

class _PreviewPane extends StatelessWidget {
  const _PreviewPane({required this.state});
  final NormalState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final it = state.focused;
    final l = context.l;
    if (it == null) {
      return Center(
        child: Text(
          l.previewSelectHint,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }
    final pv = state.preview;
    final r = pv.itemId == it.id ? pv.result : null;

    Widget header(String title, String detail, {Color? color}) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    String estimate = '';
    Color? estColor;
    if (r != null) {
      final orig = r.originalSize.toInt();
      final pct = orig == 0 ? 0 : (1 - r.data.length / orig) * 100;
      estimate =
          '${l.previewEstimate(formatBytes(r.data.length), '${pct >= 0 ? '−' : '+'}${pct.abs().toStringAsFixed(1)}')}'
          ' · ${r.width}×${r.height} · ${r.ext.toUpperCase()} ${r.quality == null ? l.lossless : 'q${r.quality}'}';
      if (pct < 0) estColor = scheme.error;
      if (r.warnings.isNotEmpty) {
        estimate +=
            ' · ⚠ ${r.warnings.map((w) => warningText(l, w)).join(' / ')}';
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header(
                l.previewOriginal,
                it.loaded
                    ? '${formatBytes(it.originalSize)} · ${it.width}×${it.height}'
                    : '',
              ),
              Expanded(
                child: _Frame(child: _OriginalImage(path: it.path)),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header(
                l.previewCompressed,
                pv.error != null ? l.previewFailed(pv.error!) : estimate,
                color: pv.error != null ? scheme.error : estColor,
              ),
              Expanded(
                child: _Frame(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (r != null)
                        LayoutBuilder(
                          builder: (context, c) => Image.memory(
                            r.data,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            cacheWidth:
                                (c.maxWidth *
                                        MediaQuery.devicePixelRatioOf(context))
                                    .round()
                                    .clamp(64, 4096),
                          ),
                        ),
                      if (pv.loading && pv.itemId == it.id)
                        const Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class _OriginalImage extends StatelessWidget {
  const _OriginalImage({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final side =
            (c.biggest.longestSide * MediaQuery.devicePixelRatioOf(context))
                .round()
                .clamp(256, 2048);
        return FutureBuilder(
          future: ThumbCache.instance.get(
            path,
            maxSide: side < 1024 ? 1024 : 2048,
          ),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            }
            return Image.memory(
              snap.data!,
              fit: BoxFit.contain,
              gaplessPlayback: true,
            );
          },
        );
      },
    );
  }
}
