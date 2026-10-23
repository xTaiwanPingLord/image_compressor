import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../src/rust/api/ecommerce.dart';
import 'section.dart';
import 'state.dart';

String platformLabel(ShopPlatform p) => switch (p) {
  ShopPlatform.shopee => 'Shopee',
  ShopPlatform.momo => 'momo',
};

String formatBytes(num b) {
  if (b >= 1000 * 1000) return '${(b / 1000 / 1000).toStringAsFixed(2)} MB';
  if (b >= 1000) return '${(b / 1000).toStringAsFixed(0)} KB';
  return '$b B';
}

/// 用系統檔案管理員開啟資料夾。
Future<void> openFolder(String path) async {
  if (Platform.isWindows) {
    await Process.run('explorer', [path]);
  } else if (Platform.isMacOS) {
    await Process.run('open', [path]);
  } else if (Platform.isLinux) {
    await Process.run('xdg-open', [path]);
  }
}

// ---------------- 設定 ----------------

Future<void> showEcomSettings(BuildContext context, EcomState s) {
  return showDialog(
    context: context,
    builder: (_) => _SettingsDialog(state: s),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.state});
  final EcomState state;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  final _form = GlobalKey<FormState>();
  late final _shopeeMax = TextEditingController(
    text: '${widget.state.settings.shopeeMaxDesc}',
  );
  late final _momoMax = TextEditingController(
    text: '${widget.state.settings.momoMaxDesc}',
  );
  late final _shopeeWidth = TextEditingController(
    text: '${widget.state.settings.shopeeMaxWidth}',
  );
  late final _momoMinLast = TextEditingController(
    text: '${widget.state.settings.momoMinLast}',
  );
  late bool _smart = widget.state.settings.smartCut;
  late double _maxQ = widget.state.settings.maxQuality.toDouble();
  late bool _c444 = widget.state.settings.chroma444;
  late Fit _fit = widget.state.defaultFit;

  @override
  void dispose() {
    for (final c in [_shopeeMax, _momoMax, _shopeeWidth, _momoMinLast]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _num(
    TextEditingController c,
    String label,
    String help,
    String? Function(int) check,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: c,
        decoration: InputDecoration(
          labelText: label,
          helperText: help,
          border: const OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        validator: (v) {
          final n = int.tryParse(v ?? '');
          if (n == null) return '請輸入數字';
          return check(n);
        },
      ),
    );
  }

  void _resetDefaults() {
    final d = defaultSettings();
    setState(() {
      _shopeeMax.text = '${d.shopeeMaxDesc}';
      _momoMax.text = '${d.momoMaxDesc}';
      _shopeeWidth.text = '${d.shopeeMaxWidth}';
      _momoMinLast.text = '${d.momoMinLast}';
      _smart = d.smartCut;
      _maxQ = d.maxQuality.toDouble();
      _c444 = d.chroma444;
      _fit = Fit.pad;
    });
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    widget.state.updateSettings(
      EcomSettings(
        shopeeMaxDesc: int.parse(_shopeeMax.text),
        momoMaxDesc: int.parse(_momoMax.text),
        smartCut: _smart,
        shopeeMaxWidth: int.parse(_shopeeWidth.text),
        momoMinLast: int.parse(_momoMinLast.text),
        maxQuality: _maxQ.round(),
        chroma444: _c444,
      ),
      _fit,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final shopeeLimit = descLimit(platform: ShopPlatform.shopee);
    final momoLimit = descLimit(platform: ShopPlatform.momo);
    return AlertDialog(
      title: const Text('電商模式設定'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                _num(
                  _shopeeMax,
                  'Shopee 詳情圖最多張數',
                  '1–$shopeeLimit',
                  (n) => n < 1 || n > shopeeLimit ? '需在 1–$shopeeLimit' : null,
                ),
                _num(
                  _momoMax,
                  'momo 詳情圖最多張數',
                  '1–$momoLimit（預設 18，保留空間給店家資訊圖）',
                  (n) => n < 1 || n > momoLimit ? '需在 1–$momoLimit' : null,
                ),
                _num(
                  _shopeeWidth,
                  'Shopee 最大寬度（px）',
                  '0 = 不限制；Shopee 前台約顯示到 1750',
                  (n) => n != 0 && n < 750 ? '需為 0 或 ≥ 750' : null,
                ),
                _num(
                  _momoMinLast,
                  'momo 詳情圖尾段最小高度（px）',
                  '低於此高度時從前一段挪高度；0 = 保持實際高度',
                  (n) => n >= 1500 ? '需小於 1500' : null,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '品質',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  '每張圖各自搜尋「符合大小限制的最高品質」，不超過下方上限',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Row(
                  children: [
                    const SizedBox(width: 72, child: Text('品質上限')),
                    Expanded(
                      child: Slider(
                        value: _maxQ,
                        min: 60,
                        max: 100,
                        divisions: 40,
                        label: '${_maxQ.round()}',
                        onChanged: (v) => setState(() => _maxQ = v),
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      child: Text(
                        '${_maxQ.round()}',
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('色度 4:4:4'),
                  subtitle: const Text('文字與細線邊緣較清晰（尤其紅字），檔案較大'),
                  value: _c444,
                  onChanged: (v) => setState(() => _c444 = v),
                ),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('智慧切點'),
                  subtitle: const Text('切段處往上 150px 內找最接近純色的橫列下刀，避免切到文字'),
                  value: _smart,
                  onChanged: (v) => setState(() => _smart = v),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Expanded(child: Text('新加入圖片的預設處理')),
                    SegmentedButton<Fit>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: Fit.pad, label: Text('補白')),
                        ButtonSegment(value: Fit.crop, label: Text('裁切')),
                      ],
                      selected: {_fit},
                      onSelectionChanged: (v) => setState(() => _fit = v.first),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _resetDefaults, child: const Text('還原預設')),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('儲存')),
      ],
    );
  }
}

// ---------------- 預檢失敗 ----------------

Future<void> showOverflow(BuildContext context, EcomReport r) {
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded),
      title: const Text('詳情圖張數超過上限'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final o in r.overflow)
            Text(
              '${platformLabel(o.platform)}：會切成 ${o.count} 張，上限 ${o.limit} 張',
            ),
          const SizedBox(height: 12),
          const Text('整批未輸出任何檔案。請刪減詳情圖，或到設定調整上限後重試。'),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}

// ---------------- 結果 ----------------

Future<void> showResult(BuildContext context, EcomReport r) {
  return showDialog(
    context: context,
    builder: (_) => _ResultDialog(report: r),
  );
}

class _ResultDialog extends StatelessWidget {
  const _ResultDialog({required this.report});
  final EcomReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final warnCount = report.outputs.where((o) => o.warnings.isNotEmpty).length;
    final platforms = report.outputs.map((o) => o.platform).toSet().toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    return AlertDialog(
      title: Text('已輸出 ${report.writtenCount} 個檔案'),
      content: SizedBox(
        width: 640,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(report.outputRoot, style: theme.textTheme.bodySmall),
            if (report.disposedCount > 0)
              Text(
                '已將 ${report.disposedCount} 個舊檔移到垃圾桶',
                style: theme.textTheme.bodySmall,
              ),
            if (warnCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '$warnCount 個檔案有警告',
                  style: TextStyle(color: scheme.error),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  for (final pf in platforms) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Text(
                        platformLabel(pf),
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    for (final o in report.outputs.where(
                      (o) => o.platform == pf,
                    ))
                      _OutputRow(o: o),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            final dirs = platforms.map((p) => p.name).toList();
            final sep = Platform.pathSeparator;
            openFolder(
              dirs.length == 1
                  ? '${report.outputRoot}$sep${dirs.first}'
                  : report.outputRoot,
            );
          },
          child: const Text('開啟資料夾'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('關閉'),
        ),
      ],
    );
  }
}

class _OutputRow extends StatelessWidget {
  const _OutputRow({required this.o});
  final OutputInfo o;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final small = theme.textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 56,
                child: Text(categoryLabel(o.category), style: small),
              ),
              Expanded(
                child: Text(o.fileName, style: theme.textTheme.bodyMedium),
              ),
              SizedBox(
                width: 100,
                child: Text(
                  '${o.width}×${o.height}',
                  style: small,
                  textAlign: TextAlign.right,
                ),
              ),
              SizedBox(
                width: 80,
                child: Text(
                  formatBytes(o.bytes.toInt()),
                  style: small,
                  textAlign: TextAlign.right,
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  'q${o.quality}',
                  style: small,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          for (final w in o.warnings)
            Padding(
              padding: const EdgeInsets.only(left: 56),
              child: Text('⚠ $w', style: small?.copyWith(color: scheme.error)),
            ),
        ],
      ),
    );
  }
}
