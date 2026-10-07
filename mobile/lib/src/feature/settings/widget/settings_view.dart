import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:four3/l10n/generated/app_localizations.dart';
import 'package:four3/src/app/locale_scope.dart';
import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/feature/app_theme/utils/theme_context_extension.dart';
import 'package:four3/src/feature/components/selectors/app_toggle.dart';
import 'package:four3/src/feature/settings/bloc/settings_bloc.dart';
import 'package:four3/src/feature/settings/bloc/settings_event.dart';
import 'package:four3/src/feature/settings/bloc/settings_state.dart';
import 'package:four3/src/feature/settings/domain/model/app_settings.dart';
import 'package:four3/src/feature/settings/widget/settings_root_scope.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class SettingsView extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsBloc bloc = SettingsRootScope.of(context);
    return BlocBuilder<SettingsBloc, SettingsState>(
      bloc: bloc,
      builder: (context, state) {
        final AppSettings settings = bloc.settings;
        final AppLocalizations l10n = context.l10n;
        void update(AppSettings value) => bloc.add(SettingsEvent$Update(value));
        final items = <Widget>[
          _SettingRow(
            icon: LucideIcons.languages,
            centerIcon: true,
            child: _LanguagePicker(scope: AppLocaleScope.of(context)),
          ),
          _SettingRow(
            icon: LucideIcons.volume2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.soundVolume,
                        style: context.textStyle.bodyStrong.copyWith(
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      '${(settings.volume * 100).round()}%',
                      style: context.textStyle.bodyStrong.copyWith(
                        color: context.colors.accent,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: settings.volume,
                  onChanged: (value) =>
                      update(settings.copyWith(volume: value)),
                ),
                if (!settings.sound)
                  Text(
                    l10n.soundDisabledInHeader,
                    style: context.textStyle.caption.copyWith(fontSize: 10),
                  ),
              ],
            ),
          ),
          _SettingSwitch(
            icon: LucideIcons.sparkles,
            value: settings.animations,
            title: l10n.animations,
            subtitle: l10n.animationsDescription,
            onChanged: (value) => update(settings.copyWith(animations: value)),
          ),
          _SettingSwitch(
            icon: LucideIcons.mousePointer2,
            value: settings.hints,
            title: l10n.movePreview,
            subtitle: l10n.movePreviewDescription,
            onChanged: (value) => update(settings.copyWith(hints: value)),
          ),
          _SettingSwitch(
            icon: LucideIcons.scanLine,
            value: settings.xrayDefault,
            title: l10n.xrayDefault,
            subtitle: l10n.xrayDefaultDescription,
            onChanged: (value) => update(settings.copyWith(xrayDefault: value)),
          ),
        ];
        return LayoutBuilder(
          builder: (context, constraints) {
            final bool landscape =
                MediaQuery.orientationOf(context) == Orientation.landscape &&
                MediaQuery.sizeOf(context).height <= 550;
            if (!landscape) return ListView(shrinkWrap: true, children: items);
            return GridView.count(
              shrinkWrap: true,
              crossAxisCount: 2,
              childAspectRatio: 3.7,
              crossAxisSpacing: 20,
              children: items,
            );
          },
        );
      },
    );
  }
}

class _LanguagePicker extends StatelessWidget {
  const new({required this.scope});

  final AppLocaleScope scope;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.language,
            style: context.textStyle.bodyStrong.copyWith(fontSize: 12),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          flex: 2,
          child: AppLanguagePicker(
            locale: scope.locale,
            onChanged: scope.setLocale,
          ),
        ),
      ],
    );
  }
}

class AppLanguagePicker extends StatefulWidget {
  const new({required this.locale, required this.onChanged, super.key});

  final Locale? locale;
  final LocaleSetter onChanged;

  @override
  State<AppLanguagePicker> createState() => _AppLanguagePickerState();
}

class _AppLanguagePickerState extends State<AppLanguagePicker> {
  bool _menuOpen = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final List<_LanguageOption> options = <_LanguageOption>[
      _LanguageOption(label: l10n.systemLanguage),
      for (final Locale supportedLocale in appSupportedLocales)
        _optionForLocale(supportedLocale, l10n),
    ];
    final _LanguageOption selected = options.firstWhere(
      (option) => option.locale == widget.locale,
      orElse: () => options.first,
    );
    final double menuWidth = math.min(
      260,
      MediaQuery.sizeOf(context).width - 32,
    );

    return PopupMenuButton<_LanguageOption>(
      useRootNavigator: true,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      tooltip: l10n.language,
      padding: EdgeInsets.zero,
      menuPadding: const EdgeInsets.all(4),
      elevation: 8,
      shadowColor: const Color(0x24162311),
      surfaceTintColor: Colors.transparent,
      color: context.colors.surface,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(8),
      constraints: BoxConstraints(
        minWidth: menuWidth,
        maxWidth: menuWidth,
        maxHeight: 360,
      ),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: context.colors.controlBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      popUpAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 180),
        reverseDuration: Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
      onOpened: () => setState(() => _menuOpen = true),
      onCanceled: () => setState(() => _menuOpen = false),
      onSelected: (option) {
        setState(() => _menuOpen = false);
        unawaited(widget.onChanged(option.locale));
      },
      itemBuilder: (context) => <PopupMenuEntry<_LanguageOption>>[
        for (final _LanguageOption option in options)
          PopupMenuItem<_LanguageOption>(
            key: ValueKey<String>(
              'language-option-${option.locale?.toLanguageTag() ?? 'system'}',
            ),
            value: option,
            padding: EdgeInsets.zero,
            child: _LanguageMenuItem(
              option: option,
              selected: option.locale == widget.locale,
              width: menuWidth - 8,
            ),
          ),
      ],
      child: Semantics(
        label: '${l10n.language}: ${selected.label}',
        button: true,
        expanded: _menuOpen,
        excludeSemantics: true,
        child: SizedBox(
          key: const ValueKey<String>('language-picker-button'),
          width: double.infinity,
          height: 44,
          child: Ink(
            decoration: BoxDecoration(
              color: _menuOpen ? const Color(0xFFF4F6FE) : Colors.white,
              border: Border.all(
                color: _menuOpen
                    ? context.colors.accent
                    : context.colors.controlBorder,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  _LanguageMarker(flagCode: selected.flagCode),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      selected.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyle.captionStrong.copyWith(
                        color: _menuOpen
                            ? context.colors.accent
                            : context.colors.ink,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _menuOpen ? .5 : 0,
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      LucideIcons.chevronDown,
                      size: 15,
                      color: _menuOpen
                          ? context.colors.accent
                          : context.colors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageMenuItem extends StatelessWidget {
  const new({
    required this.option,
    required this.selected,
    required this.width,
  });

  final _LanguageOption option;
  final bool selected;
  final double width;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: Container(
      width: width,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFE8EDFE) : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          _LanguageMarker(flagCode: option.flagCode),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              option.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textStyle.bodyStrong.copyWith(
                color: selected ? context.colors.accent : context.colors.ink,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ExcludeSemantics(
            child: SizedBox(
              width: 18,
              child: selected
                  ? Icon(
                      LucideIcons.check,
                      size: 17,
                      color: context.colors.accent,
                    )
                  : null,
            ),
          ),
        ],
      ),
    ),
  );
}

class _LanguageMarker extends StatelessWidget {
  const new({this.flagCode});

  final String? flagCode;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: 24,
      height: 18,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.colors.ivory,
        border: Border.all(color: context.colors.controlBorder),
        borderRadius: BorderRadius.circular(3),
      ),
      child: flagCode == null
          ? Icon(LucideIcons.globe2, size: 13, color: context.colors.muted)
          : SvgPicture.asset(
              'assets/flags/$flagCode.svg',
              fit: BoxFit.cover,
              excludeFromSemantics: true,
            ),
    ),
  );
}

final class _LanguageOption {
  const new({required this.label, this.locale, this.flagCode});

  final String label;
  final Locale? locale;
  final String? flagCode;
}

_LanguageOption _optionForLocale(Locale locale, AppLocalizations l10n) =>
    switch (locale.toLanguageTag()) {
      'en' => _LanguageOption(
        locale: locale,
        label: l10n.languageEnglish,
        flagCode: 'gb',
      ),
      'ru' => _LanguageOption(
        locale: locale,
        label: l10n.languageRussian,
        flagCode: 'ru',
      ),
      'es' => _LanguageOption(
        locale: locale,
        label: l10n.languageSpanish,
        flagCode: 'es',
      ),
      'fr' => _LanguageOption(
        locale: locale,
        label: l10n.languageFrench,
        flagCode: 'fr',
      ),
      'pt-BR' => _LanguageOption(
        locale: locale,
        label: l10n.languagePortugueseBrazil,
        flagCode: 'br',
      ),
      'de' => _LanguageOption(
        locale: locale,
        label: l10n.languageGerman,
        flagCode: 'de',
      ),
      final String tag => throw UnsupportedError('Unsupported locale: $tag'),
    };

class _SettingRow extends StatelessWidget {
  const new({required this.icon, required this.child, this.centerIcon = false});

  final IconData icon;
  final Widget child;
  final bool centerIcon;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 54),
    padding: EdgeInsets.symmetric(
      vertical: MediaQuery.sizeOf(context).width <= 650 ? 10 : 18,
    ),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.colors.border)),
    ),
    child: Row(
      crossAxisAlignment: centerIcon
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: centerIcon ? 0 : 2),
          child: Icon(icon, size: 20, color: const Color(0xFF6D765F)),
        ),
        SizedBox(width: MediaQuery.sizeOf(context).width <= 650 ? 8 : 15),
        Expanded(child: child),
      ],
    ),
  );
}

class _SettingSwitch extends StatelessWidget {
  const new({
    required this.icon,
    required this.value,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  final IconData icon;
  final bool value;
  final String title;
  final String subtitle;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => _SettingRow(
    icon: icon,
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: context.textStyle.bodyStrong.copyWith(fontSize: 12),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: context.textStyle.caption.copyWith(fontSize: 10),
              ),
            ],
          ),
        ),
        AppToggle(value: value, onChanged: onChanged, semanticLabel: title),
      ],
    ),
  );
}
