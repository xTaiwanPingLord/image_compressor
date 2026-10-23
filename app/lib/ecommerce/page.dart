import 'package:flutter/material.dart';

import '../src/rust/api/ecommerce.dart';
import 'dialogs.dart';
import 'section.dart';
import 'state.dart';

/// 電商模式頁面。
class EcommercePage extends StatefulWidget {
  const EcommercePage({super.key, required this.state});
  final EcomState state;

  @override
  State<EcommercePage> createState() => _EcommercePageState();
}

class _EcommercePageState extends State<EcommercePage> {
  late final _nameCtrl = TextEditingController(text: widget.state.name);

  EcomState get s => widget.state;

  @override
  void initState() {
    super.initState();
    s.addListener(_syncName);
  }

  @override
  void dispose() {
    s.removeListener(_syncName);
    _nameCtrl.dispose();
    super.dispose();
  }

  void _syncName() {
    if (_nameCtrl.text != s.name) {
      _nameCtrl.value = TextEditingValue(
        text: s.name,
        selection: TextSelection.collapsed(offset: s.name.length),
      );
    }
  }

  Future<void> _run() async {
    final res = await s.run();
    if (!mounted) return;
    switch (res.stage) {
      case EcomStage.done:
        final r = res.report!;
        if (r.overflow.isNotEmpty) {
          await showOverflow(context, r);
        } else {
          await showResult(context, r);
        }
      case EcomStage.failed:
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.error_outline),
            title: const Text('執行失敗'),
            content: SelectableText(res.error ?? '未知錯誤'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('關閉'),
              ),
            ],
          ),
        );
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Column(
        children: [
          _toolbar(context),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => c.maxWidth < 720 ? _tabs() : _stacked(),
            ),
          ),
          _statusBar(context),
        ],
      ),
    );
  }

  Widget _toolbar(BuildContext context) {
    final block = s.blockReason;
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 260,
            child: TextField(
              controller: _nameCtrl,
              enabled: !s.running,
              decoration: const InputDecoration(
                labelText: 'name',
                hintText: '例如 223_ssd',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: s.setName,
            ),
          ),
          for (final pf in ShopPlatform.values)
            FilterChip(
              label: Text(platformLabel(pf)),
              selected: s.platforms.contains(pf),
              onSelected: s.running ? null : (v) => s.togglePlatform(pf, v),
            ),
          Tooltip(
            message: block ?? '',
            child: FilledButton.icon(
              onPressed: block == null ? _run : null,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('執行'),
            ),
          ),
          IconButton(
            tooltip: '設定',
            onPressed: s.running ? null : () => showEcomSettings(context, s),
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: '全部清空',
            onPressed: s.running || s.totalCount == 0 ? null : s.clearAll,
            icon: const Icon(Icons.clear_all),
          ),
        ],
      ),
    );
  }

  Widget _stacked() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in ImgCategory.values) ...[
            EcomSection(state: s, category: c),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }

  Widget _tabs() {
    return DefaultTabController(
      length: ImgCategory.values.length,
      child: Column(
        children: [
          TabBar(
            tabs: [
              for (final c in ImgCategory.values)
                Tab(text: '${categoryLabel(c)} (${s.sections[c]!.length})'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final c in ImgCategory.values)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: EcomSection(state: s, category: c, expand: true),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBar(BuildContext context) {
    final theme = Theme.of(context);
    final p = s.progress;
    String text;
    double? value;
    if (s.running) {
      switch (p?.stage) {
        case EcomStage.encoding:
          text = '壓縮中 ${p!.done} / ${p.total}';
          value = p.total == 0 ? null : p.done / p.total;
        case EcomStage.writing:
          text = '寫入檔案…';
        default:
          text = '讀取與排版…';
      }
    } else {
      final st = s.settings;
      text =
          '共 ${s.totalCount} 張 · 詳情圖上限 Shopee ${st.shopeeMaxDesc} / momo ${st.momoMaxDesc}'
          ' · 智慧切點${st.smartCut ? '開' : '關'}'
          ' · Shopee 最大寬 ${st.shopeeMaxWidth == 0 ? '不限' : st.shopeeMaxWidth}';
    }
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (s.running) LinearProgressIndicator(value: value, minHeight: 3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(text, style: theme.textTheme.bodySmall),
            ),
          ),
        ],
      ),
    );
  }
}
