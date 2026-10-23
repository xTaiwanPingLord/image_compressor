import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../platform/android_files.dart';
import '../src/rust/api/normal.dart';
import 'state.dart';

/// 右側設定：壓縮（含縮放）/ 輸出（含中繼資料）兩分頁。
class NormalSettingsPanel extends StatelessWidget {
  const NormalSettingsPanel({super.key, required this.state});
  final NormalState state;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: l.tabCompression),
              Tab(text: l.tabOutput),
            ],
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: state,
              builder: (context, _) => TabBarView(
                children: [
                  _CompressionTab(state: state),
                  _OutputTab(state: state),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: state.running ? null : state.resetSettings,
                icon: const Icon(Icons.restart_alt, size: 18),
                label: Text(context.l.resetDefaults),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              title,
              style: t.textTheme.labelLarge?.copyWith(
                color: t.colorScheme.primary,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

/// 拖動中只更新顯示，放開才寫入設定。
class _CommitSlider extends StatefulWidget {
  const _CommitSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onCommit,
    this.enabled = true,
  });
  final String label;
  final int value;
  final int min;
  final int max;
  final bool enabled;
  final ValueChanged<int> onCommit;

  @override
  State<_CommitSlider> createState() => _CommitSliderState();
}

class _CommitSliderState extends State<_CommitSlider> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final v = _drag ?? widget.value.toDouble();
    return Row(
      children: [
        SizedBox(width: 72, child: Text(widget.label)),
        Expanded(
          child: Slider(
            value: v.clamp(widget.min.toDouble(), widget.max.toDouble()),
            min: widget.min.toDouble(),
            max: widget.max.toDouble(),
            divisions: widget.max - widget.min,
            onChanged: widget.enabled ? (x) => setState(() => _drag = x) : null,
            onChangeEnd: widget.enabled
                ? (x) {
                    setState(() => _drag = null);
                    widget.onCommit(x.round());
                  }
                : null,
          ),
        ),
        SizedBox(
          width: 32,
          child: Text('${v.round()}', textAlign: TextAlign.right),
        ),
      ],
    );
  }
}

/// 數字欄位，停止輸入約 400ms 後才寫入設定。
class _DebouncedNumber extends StatefulWidget {
  const _DebouncedNumber({
    super.key,
    required this.label,
    required this.value,
    required this.onCommit,
    this.suffix,
    this.enabled = true,
  });
  final String label;
  final int value;
  final String? suffix;
  final bool enabled;
  final ValueChanged<int> onCommit;

  @override
  State<_DebouncedNumber> createState() => _DebouncedNumberState();
}

class _DebouncedNumberState extends State<_DebouncedNumber> {
  late final _c = TextEditingController(text: '${widget.value}');
  Timer? _t;

  @override
  void didUpdateWidget(covariant _DebouncedNumber old) {
    super.didUpdateWidget(old);
    if (_t == null && int.tryParse(_c.text) != widget.value) {
      _c.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _changed(String s) {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 400), () {
      _t = null;
      final n = int.tryParse(s);
      if (n != null && n >= 1 && n != widget.value) widget.onCommit(n);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: _c,
        enabled: widget.enabled,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: widget.label,
          suffixText: widget.suffix,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: _changed,
      ),
    );
  }
}

Widget _switch(
  String title,
  bool v,
  ValueChanged<bool>? onChanged, {
  String? subtitle,
}) => SwitchListTile(
  contentPadding: EdgeInsets.zero,
  dense: true,
  title: Text(title),
  subtitle: subtitle == null ? null : Text(subtitle),
  value: v,
  onChanged: onChanged,
);

Widget _dropdown<T>(
  String label,
  T value,
  Map<T, String> items,
  ValueChanged<T>? onChanged,
) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 6),
  child: DropdownButtonFormField<T>(
    initialValue: value,
    isDense: true,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
    ),
    items: [
      for (final e in items.entries)
        DropdownMenuItem(
          value: e.key,
          child: Text(e.value, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: onChanged == null
        ? null
        : (v) => v == null ? null : onChanged(v),
  ),
);

// ---------------- 壓縮 ----------------

class _CompressionTab extends StatelessWidget {
  const _CompressionTab({required this.state});
  final NormalState state;

  @override
  Widget build(BuildContext context) {
    final s = state.settings;
    final off = state.running;
    final l = context.l;
    void set(void Function() f) {
      f();
      state.settingsChanged();
    }

    final kb = (s.maxSize / 1000).round();
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        _Section(l.secMode, [
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: false, label: Text(l.modeQuality)),
              ButtonSegment(value: true, label: Text(l.modeTargetSize)),
            ],
            selected: {s.sizeMode},
            onSelectionChanged: off || s.lossless
                ? null
                : (v) => set(() => s.maxSize = v.first ? 500 * 1000 : 0),
          ),
          const SizedBox(height: 4),
          _switch(
            l.lossless,
            s.lossless,
            off ? null : (v) => set(() => s.lossless = v),
            subtitle: l.losslessHelp,
          ),
          if (!s.sizeMode)
            _CommitSlider(
              label: l.modeQuality,
              value: s.quality,
              min: 1,
              max: 100,
              enabled: !off && !s.lossless,
              onCommit: (v) => set(() => s.quality = v),
            )
          else
            _DebouncedNumber(
              label: l.modeTargetSize,
              suffix: 'KB',
              value: kb,
              enabled: !off && !s.lossless,
              onCommit: (v) => set(() => s.maxSize = v * 1000),
            ),
        ]),
        _ResizeSection(state: state),
        _Section('JPEG', [
          _dropdown<ChromaSubsampling>(l.chromaSubsampling, s.jpegChroma, {
            ChromaSubsampling.auto: l.chromaAuto,
            ChromaSubsampling.s444: l.chroma444,
            ChromaSubsampling.s422: '4:2:2',
            ChromaSubsampling.s420: l.chroma420,
          }, off || s.lossless ? null : (v) => set(() => s.jpegChroma = v)),
        ]),
        _Section('PNG', [
          _CommitSlider(
            label: l.pngOptimize,
            value: s.pngLevel,
            min: 0,
            max: 6,
            enabled: !off,
            onCommit: (v) => set(() => s.pngLevel = v),
          ),
          Text(l.pngOptimizeHelp, style: Theme.of(context).textTheme.bodySmall),
        ]),
      ],
    );
  }
}

// ---------------- 縮放（放在壓縮分頁內） ----------------

class _ResizeSection extends StatelessWidget {
  const _ResizeSection({required this.state});
  final NormalState state;

  @override
  Widget build(BuildContext context) {
    final s = state.settings;
    final off = state.running;
    final l = context.l;
    void set(void Function() f) {
      f();
      state.settingsChanged();
    }

    final unit = s.resize == ResizeMode.percentage ? '%' : 'px';
    String label(ResizeMode m) => switch (m) {
      ResizeMode.percentage => l.resizePercentage,
      ResizeMode.width => l.valueWidth,
      ResizeMode.height => l.valueHeight,
      ResizeMode.longEdge => l.resizeLongEdge,
      ResizeMode.shortEdge => l.resizeShortEdge,
      ResizeMode.fitBox => l.valueMaxWidth,
      ResizeMode.none => '',
    };

    return _Section(l.secResize, [
      _dropdown<ResizeMode>(
        l.resizeMethod,
        s.resize,
        {
          ResizeMode.none: l.resizeNone,
          ResizeMode.percentage: l.resizePercentage,
          ResizeMode.width: l.resizeWidth,
          ResizeMode.height: l.resizeHeight,
          ResizeMode.longEdge: l.resizeLongEdge,
          ResizeMode.shortEdge: l.resizeShortEdge,
          ResizeMode.fitBox: l.resizeFitBox,
        },
        off
            ? null
            : (v) => set(() {
                s.resize = v;
                if (v == ResizeMode.percentage && s.resizeValue > 400) {
                  s.resizeValue = 50;
                }
                if (v != ResizeMode.percentage &&
                    v != ResizeMode.none &&
                    s.resizeValue <= 100) {
                  s.resizeValue = 1920;
                }
                if (v == ResizeMode.fitBox && s.resizeValue2 == 0) {
                  s.resizeValue2 = 1920;
                }
              }),
      ),
      if (s.resize != ResizeMode.none)
        _DebouncedNumber(
          key: ValueKey('rv-${s.resize}'),
          label: label(s.resize),
          suffix: unit,
          value: s.resizeValue,
          enabled: !off,
          onCommit: (v) => set(() => s.resizeValue = v),
        ),
      if (s.resize == ResizeMode.fitBox)
        _DebouncedNumber(
          label: l.valueMaxHeight,
          suffix: 'px',
          value: s.resizeValue2,
          enabled: !off,
          onCommit: (v) => set(() => s.resizeValue2 = v),
        ),
      if (s.resize != ResizeMode.none)
        _switch(
          l.noEnlarge,
          s.noEnlarge,
          off ? null : (v) => set(() => s.noEnlarge = v),
          subtitle: l.noEnlargeHelp,
        ),
      const SizedBox(height: 8),
      Text(l.resizeNote, style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

// ---------------- 輸出 ----------------

class _OutputTab extends StatefulWidget {
  const _OutputTab({required this.state});
  final NormalState state;

  @override
  State<_OutputTab> createState() => _OutputTabState();
}

class _OutputTabState extends State<_OutputTab> {
  late final _suffix = TextEditingController(
    text: widget.state.settings.suffix,
  );
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    _suffix.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final s = state.settings;
    final off = state.running;
    final l = context.l;
    final theme = Theme.of(context);
    void set(void Function() f) {
      f();
      state.settingsChanged();
    }

    final custom = s.outputDir.trim().isNotEmpty;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        _Section(l.secFormat, [
          _dropdown<OutFormat>(l.outputFormat, s.format, {
            OutFormat.same: l.formatSame,
            OutFormat.jpeg: 'JPEG',
            OutFormat.png: 'PNG',
            OutFormat.webp: 'WebP',
          }, off ? null : (v) => set(() => s.format = v)),
        ]),
        _Section(l.secLocation, [
          RadioGroup<bool>(
            groupValue: custom,
            onChanged: (v) {
              if (off || v == null) return;
              if (!v) {
                set(() => s.outputDir = '');
              } else {
                _pickDir();
              }
            },
            child: Column(
              children: [
                RadioListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: false,
                  title: Text(l.sameFolder),
                ),
                RadioListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: true,
                  title: Text(l.customFolder),
                ),
              ],
            ),
          ),
          if (custom)
            Row(
              children: [
                Expanded(
                  child: Text(
                    treeDirLabel(s.outputDir),
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: off ? null : _pickDir,
                  child: Text(l.change),
                ),
              ],
            ),
          if (custom)
            _switch(
              l.keepStructure,
              s.keepStructure,
              off ? null : (v) => set(() => s.keepStructure = v),
              subtitle: l.keepStructureHelp,
            ),
        ]),
        _Section(l.secFileName, [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: TextField(
              controller: _suffix,
              enabled: !off,
              decoration: InputDecoration(
                labelText: l.suffix,
                hintText: '_compressed',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                _t?.cancel();
                _t = Timer(
                  const Duration(milliseconds: 400),
                  () => set(() => s.suffix = v),
                );
              },
            ),
          ),
          if (state.overwritesOriginal)
            Text(
              AndroidFiles.supported
                  ? l.overwriteWarningAndroid
                  : l.overwriteWarning,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ]),
        _Section(l.secMetadata, [
          _switch(
            l.keepMetadata,
            s.keepMetadata,
            off ? null : (v) => set(() => s.keepMetadata = v),
            subtitle: l.keepMetadataHelp,
          ),
          // Android 的 SAF 無法設定檔案日期
          if (!AndroidFiles.supported)
            _switch(
              l.keepDates,
              s.keepDates,
              off ? null : (v) => set(() => s.keepDates = v),
            ),
        ]),
        _Section(l.secOther, [
          _switch(
            l.skipIfBigger,
            s.skipIfBigger,
            off ? null : (v) => set(() => s.skipIfBigger = v),
            subtitle: l.skipIfBiggerHelp,
          ),
        ]),
      ],
    );
  }

  Future<void> _pickDir() async {
    if (AndroidFiles.supported) {
      final t = await AndroidFiles.instance.pickFolder();
      if (t == null) return;
      widget.state.settings.outputDir = encodeTreeDir(t, '');
      widget.state.settingsChanged();
      return;
    }
    final d = await getDirectoryPath();
    if (d == null) return;
    widget.state.settings.outputDir = d;
    widget.state.settingsChanged();
  }
}
