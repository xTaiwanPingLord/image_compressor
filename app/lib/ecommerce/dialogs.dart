import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../platform/android_files.dart';
import '../src/rust/api/ecommerce.dart';
import 'state.dart';

/// 用系統檔案管理員開啟資料夾。
Future<void> openFolder(String path) async {
  final tree = decodeTreeDir(path);
  if (tree != null) {
    await AndroidFiles.instance.openTree(tree.$1, tree.$2);
    return;
  }
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
  // 窄螢幕與普通模式一致：底部彈出；寬螢幕用對話框
  if (MediaQuery.sizeOf(context).width < 720) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: _SettingsDialog(state: s, sheet: true),
      ),
    );
  }
  return showDialog(
    context: context,
    builder: (_) => _SettingsDialog(state: s),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.state, this.sheet = false});
  final EcomState state;
  final bool sheet;

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
  late final Set<ShopPlatform> _platforms = {...widget.state.platforms};

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
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        validator: (v) {
          final n = int.tryParse(v ?? '');
          if (n == null) return context.l.enterNumber;
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
      _platforms
        ..clear()
        ..addAll(ShopPlatform.values);
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
    widget.state.setPlatforms(_platforms);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final shopeeLimit = descLimit(platform: ShopPlatform.shopee);
    final momoLimit = descLimit(platform: ShopPlatform.momo);
    final l = context.l;
    final form = Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.ecomPlatforms, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final pf in ShopPlatform.values)
                FilterChip(
                  label: Text(platformLabel(pf)),
                  selected: _platforms.contains(pf),
                  onSelected: (v) => setState(
                    () => v ? _platforms.add(pf) : _platforms.remove(pf),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const SizedBox(height: 8),
          _num(
            _shopeeMax,
            l.ecomShopeeMaxDesc,
            l.rangeHelp(1, shopeeLimit),
            (n) =>
                n < 1 || n > shopeeLimit ? l.rangeError(1, shopeeLimit) : null,
          ),
          _num(
            _momoMax,
            l.ecomMomoMaxDesc,
            l.ecomMomoMaxDescHelp(1, momoLimit),
            (n) => n < 1 || n > momoLimit ? l.rangeError(1, momoLimit) : null,
          ),
          _num(
            _shopeeWidth,
            l.ecomShopeeMaxWidth,
            l.ecomShopeeMaxWidthHelp,
            (n) => n != 0 && n < 750 ? l.ecomShopeeMaxWidthError : null,
          ),
          _num(
            _momoMinLast,
            l.ecomMomoMinLast,
            l.ecomMomoMinLastHelp,
            (n) => n >= 1500 ? l.ecomMomoMinLastError : null,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l.ecomQuality,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Text(l.ecomQualityHelp, style: Theme.of(context).textTheme.bodySmall),
          Row(
            children: [
              SizedBox(width: 96, child: Text(l.ecomMaxQuality)),
              Expanded(
                child: Slider(
                  value: _maxQ,
                  min: 60,
                  max: 100,
                  divisions: 40,
                  onChanged: (v) => setState(() => _maxQ = v),
                ),
              ),
              SizedBox(
                width: 32,
                child: Text('${_maxQ.round()}', textAlign: TextAlign.right),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.ecomChroma444),
            subtitle: Text(l.ecomChroma444Help),
            value: _c444,
            onChanged: (v) => setState(() => _c444 = v),
          ),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.ecomSmartCut),
            subtitle: Text(l.ecomSmartCutHelp),
            value: _smart,
            onChanged: (v) => setState(() => _smart = v),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text(l.ecomDefaultFit)),
              SegmentedButton<Fit>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: Fit.pad, label: Text(l.pad)),
                  ButtonSegment(value: Fit.crop, label: Text(l.crop)),
                ],
                selected: {_fit},
                onSelectionChanged: (v) => setState(() => _fit = v.first),
              ),
            ],
          ),
        ],
      ),
    );
    final actions = [
      TextButton(onPressed: _resetDefaults, child: Text(l.resetDefaults)),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(l.cancel),
      ),
      FilledButton(onPressed: _save, child: Text(l.save)),
    ];
    if (widget.sheet) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                l.ecomSettingsTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: form,
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: actions,
              ),
            ),
          ],
        ),
      );
    }
    return AlertDialog(
      title: Text(l.ecomSettingsTitle),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: form)),
      actions: actions,
    );
  }
}

// ---------------- 預檢失敗 ----------------

Future<void> showOverflow(BuildContext context, EcomReport r) {
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded),
      title: Text(context.l.ecomOverflowTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final o in r.overflow)
            Text(
              context.l.ecomOverflowLine(
                platformLabel(o.platform),
                o.count,
                o.limit,
              ),
            ),
          const SizedBox(height: 12),
          Text(context.l.ecomOverflowHelp),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l.gotIt),
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
    final l = context.l;
    final warnCount = report.outputs.where((o) => o.warnings.isNotEmpty).length;
    final platforms = report.outputs.map((o) => o.platform).toSet().toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    return AlertDialog(
      title: Text(l.ecomResultTitle(report.writtenCount)),
      content: SizedBox(
        width: 640,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              treeDirLabel(report.outputRoot),
              style: theme.textTheme.bodySmall,
            ),
            if (report.disposedCount > 0)
              Text(
                l.ecomDisposed(report.disposedCount),
                style: theme.textTheme.bodySmall,
              ),
            if (warnCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  l.ecomWarnCount(warnCount),
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
            final tree = decodeTreeDir(report.outputRoot);
            openFolder(
              dirs.length != 1
                  ? report.outputRoot
                  : tree != null
                  ? encodeTreeDir(tree.$1, dirs.first)
                  : '${report.outputRoot}$sep${dirs.first}',
            );
          },
          child: Text(l.openFolder),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.close),
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
    final cat = categoryLabel(context.l, o.category);
    final dims = '${o.width}×${o.height}';
    final size = formatBytes(o.bytes.toInt());
    final warnings = [
      for (final w in o.warnings)
        Text(
          '⚠ ${warningText(context.l, w)}',
          style: small?.copyWith(color: scheme.error),
        ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        // 窄螢幕：檔名一行（過長以 … 省略），下一行放類別與數值
        if (c.maxWidth < 480) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  o.fileName,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$cat · $dims · $size · q${o.quality}',
                  style: small,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                ...warnings,
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(width: 56, child: Text(cat, style: small)),
                  Expanded(
                    child: Text(
                      o.fileName,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: 100,
                    child: Text(dims, style: small, textAlign: TextAlign.right),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text(size, style: small, textAlign: TextAlign.right),
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
              for (final w in warnings)
                Padding(padding: const EdgeInsets.only(left: 56), child: w),
            ],
          ),
        );
      },
    );
  }
}
