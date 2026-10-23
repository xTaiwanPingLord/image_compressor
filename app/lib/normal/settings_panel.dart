import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../src/rust/api/normal.dart';
import 'state.dart';

/// 右側設定：壓縮 / 縮放 / 輸出 三分頁。
class NormalSettingsPanel extends StatelessWidget {
  const NormalSettingsPanel({super.key, required this.state});
  final NormalState state;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: '壓縮'),
              Tab(text: '縮放'),
              Tab(text: '輸出'),
            ],
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: state,
              builder: (context, _) => TabBarView(
                children: [
                  _CompressionTab(state: state),
                  _ResizeTab(state: state),
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
                label: const Text('還原預設'),
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
            label: v.round().toString(),
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
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
    ),
    items: [
      for (final e in items.entries)
        DropdownMenuItem(value: e.key, child: Text(e.value)),
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
    void set(void Function() f) {
      f();
      state.settingsChanged();
    }

    final kb = (s.maxSize / 1000).round();
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        _Section('模式', [
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('品質')),
              ButtonSegment(value: true, label: Text('目標大小')),
            ],
            selected: {s.sizeMode},
            onSelectionChanged: off || s.lossless
                ? null
                : (v) => set(() => s.maxSize = v.first ? 500 * 1000 : 0),
          ),
          const SizedBox(height: 4),
          _switch(
            '無損',
            s.lossless,
            off ? null : (v) => set(() => s.lossless = v),
            subtitle: 'JPEG 只重新最佳化編碼、PNG 用 oxipng、WebP 用無損模式',
          ),
          if (!s.sizeMode)
            _CommitSlider(
              label: '品質',
              value: s.quality,
              min: 1,
              max: 100,
              enabled: !off && !s.lossless,
              onCommit: (v) => set(() => s.quality = v),
            )
          else
            _DebouncedNumber(
              label: '目標大小',
              suffix: 'KB',
              value: kb,
              enabled: !off && !s.lossless,
              onCommit: (v) => set(() => s.maxSize = v * 1000),
            ),
        ]),
        _Section('JPEG', [
          _dropdown<ChromaSubsampling>('色度取樣', s.jpegChroma, const {
            ChromaSubsampling.auto: '自動（品質 ≥ 90 用 4:4:4）',
            ChromaSubsampling.s444: '4:4:4（最清晰）',
            ChromaSubsampling.s422: '4:2:2',
            ChromaSubsampling.s420: '4:2:0（最小）',
          }, off || s.lossless ? null : (v) => set(() => s.jpegChroma = v)),
        ]),
        _Section('PNG', [
          _CommitSlider(
            label: '最佳化',
            value: s.pngLevel,
            min: 0,
            max: 6,
            enabled: !off,
            onCommit: (v) => set(() => s.pngLevel = v),
          ),
          Text(
            '等級越高越小但越慢；有損 PNG 以品質決定調色盤色數',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ]),
        _Section('中繼資料', [
          _switch(
            '保留 EXIF 等中繼資料',
            s.keepMetadata,
            off ? null : (v) => set(() => s.keepMetadata = v),
            subtitle: 'ICC 色彩描述檔一律保留',
          ),
          _switch(
            '保留檔案日期',
            s.keepDates,
            off ? null : (v) => set(() => s.keepDates = v),
          ),
        ]),
      ],
    );
  }
}

// ---------------- 縮放 ----------------

class _ResizeTab extends StatelessWidget {
  const _ResizeTab({required this.state});
  final NormalState state;

  @override
  Widget build(BuildContext context) {
    final s = state.settings;
    final off = state.running;
    void set(void Function() f) {
      f();
      state.settingsChanged();
    }

    final unit = s.resize == ResizeMode.percentage ? '%' : 'px';
    String label(ResizeMode m) => switch (m) {
      ResizeMode.percentage => '百分比',
      ResizeMode.width => '寬度',
      ResizeMode.height => '高度',
      ResizeMode.longEdge => '長邊',
      ResizeMode.shortEdge => '短邊',
      ResizeMode.fitBox => '寬度上限',
      ResizeMode.none => '',
    };

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        _Section('縮放方式', [
          _dropdown<ResizeMode>(
            '方式',
            s.resize,
            const {
              ResizeMode.none: '不縮放',
              ResizeMode.percentage: '百分比',
              ResizeMode.width: '固定寬度',
              ResizeMode.height: '固定高度',
              ResizeMode.longEdge: '長邊',
              ResizeMode.shortEdge: '短邊',
              ResizeMode.fitBox: '縮放到框內（寬 × 高）',
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
              label: '高度上限',
              suffix: 'px',
              value: s.resizeValue2,
              enabled: !off,
              onCommit: (v) => set(() => s.resizeValue2 = v),
            ),
          if (s.resize != ResizeMode.none)
            _switch(
              '不放大',
              s.noEnlarge,
              off ? null : (v) => set(() => s.noEnlarge = v),
              subtitle: '比目標小的圖片維持原尺寸',
            ),
          const SizedBox(height: 8),
          Text(
            '一律等比縮放（Lanczos3）',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ]),
      ],
    );
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
    final theme = Theme.of(context);
    void set(void Function() f) {
      f();
      state.settingsChanged();
    }

    final custom = s.outputDir.trim().isNotEmpty;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        _Section('格式', [
          _dropdown<OutFormat>('輸出格式', s.format, const {
            OutFormat.same: '與原檔相同（BMP / TIFF / GIF 轉 PNG）',
            OutFormat.jpeg: 'JPEG',
            OutFormat.png: 'PNG',
            OutFormat.webp: 'WebP',
          }, off ? null : (v) => set(() => s.format = v)),
        ]),
        _Section('位置', [
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
            child: const Column(
              children: [
                RadioListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: false,
                  title: Text('與原檔相同資料夾'),
                ),
                RadioListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: true,
                  title: Text('指定資料夾'),
                ),
              ],
            ),
          ),
          if (custom)
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.outputDir,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: off ? null : _pickDir,
                  child: const Text('變更…'),
                ),
              ],
            ),
          if (custom)
            _switch(
              '保留資料夾結構',
              s.keepStructure,
              off ? null : (v) => set(() => s.keepStructure = v),
              subtitle: '拖入資料夾時，依子資料夾分別輸出',
            ),
        ]),
        _Section('檔名', [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: TextField(
              controller: _suffix,
              enabled: !off,
              decoration: const InputDecoration(
                labelText: '後綴',
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
              '同資料夾且無後綴：會覆寫原檔（原檔先移到垃圾桶）',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ]),
        _Section('其他', [
          _switch(
            '壓縮後較大時保留原檔',
            s.skipIfBigger,
            off ? null : (v) => set(() => s.skipIfBigger = v),
            subtitle: '格式與尺寸不變時，改輸出原檔內容',
          ),
        ]),
      ],
    );
  }

  Future<void> _pickDir() async {
    final d = await getDirectoryPath();
    if (d == null) return;
    widget.state.settings.outputDir = d;
    widget.state.settingsChanged();
  }
}
