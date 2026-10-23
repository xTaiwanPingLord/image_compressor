import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'app_settings.dart';
import 'theme.dart';

/// 設定頁：語言、主題、色彩、字體、關於。
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.settings,
    this.systemColorAvailable = false,
  });
  final AppSettings settings;
  final bool systemColorAvailable;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            children: [
              Text(l.navSettings, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              _Card(
                title: l.setLanguage,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<AppLanguage>(
                    showSelectedIcon: false,
                    segments: [
                      for (final v in AppLanguage.values)
                        ButtonSegment(value: v, label: Text(v.nativeName)),
                    ],
                    selected: {settings.language},
                    onSelectionChanged: (v) => settings.setLanguage(v.first),
                  ),
                ),
              ),
              _Card(
                title: l.setTheme,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: const Icon(Icons.brightness_auto_outlined),
                        label: Text(l.themeSystem),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: const Icon(Icons.light_mode_outlined),
                        label: Text(l.themeLight),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: const Icon(Icons.dark_mode_outlined),
                        label: Text(l.themeDark),
                      ),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: (v) => settings.setThemeMode(v.first),
                  ),
                ),
              ),
              _Card(
                title: l.setColor,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (systemColorAvailable)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l.colorFollowSystem),
                        subtitle: Text(l.colorFollowSystemHelp),
                        value: settings.useSystemColor,
                        onChanged: settings.setUseSystemColor,
                      ),
                    Opacity(
                      opacity: settings.useSystemColor && systemColorAvailable
                          ? 0.4
                          : 1,
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (var i = 0; i < seedColors.length; i++)
                            _Swatch(
                              color: seedColors[i],
                              selected:
                                  !(settings.useSystemColor &&
                                      systemColorAvailable) &&
                                  settings.seedIndex == i,
                              onTap: () => settings.setSeed(i),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _Card(
                title: l.setFont,
                child: RadioGroup<AppFont>(
                  groupValue: settings.font,
                  onChanged: (v) => v == null ? null : settings.setFont(v),
                  child: Column(
                    children: [
                      _FontOption(
                        value: AppFont.system,
                        title: l.fontDefault,
                        sample: l.fontSample,
                        family: null,
                      ),
                      _FontOption(
                        value: AppFont.miSans,
                        title: 'MiSans',
                        sample: l.fontSample,
                        family: miSansPrimary(settings.language),
                        fallback: [miSansSecondary(settings.language)],
                      ),
                    ],
                  ),
                ),
              ),
              _Card(
                title: l.setAbout,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.appTitle, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(l.aboutFontCredit, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 16),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? scheme.onSurface : Colors.transparent,
              width: 3,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, color: Colors.white, size: 20)
              : null,
        ),
      ),
    );
  }
}

class _FontOption extends StatelessWidget {
  const _FontOption({
    required this.value,
    required this.title,
    required this.sample,
    required this.family,
    this.fallback,
  });
  final AppFont value;
  final String title;
  final String sample;
  final String? family;

  /// 預覽時的備用字體（MiSans 繁簡互補）；null = 沿用主題設定
  final List<String>? fallback;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 「預設」需明確指定平台預設字體，否則會沿用目前主題（可能是 MiSans）
    final systemFamily = Typography.material2021(platform: theme.platform)
        .black
        .titleMedium
        ?.fontFamily;
    return RadioListTile<AppFont>(
      contentPadding: EdgeInsets.zero,
      value: value,
      title: Text(title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sample,
            style: theme.textTheme.titleMedium?.copyWith(
              fontFamily: family ?? systemFamily,
              fontFamilyFallback:
                  fallback ?? theme.textTheme.titleMedium?.fontFamilyFallback,
            ),
          ),
        ],
      ),
    );
  }
}
