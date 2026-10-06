import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:four3/l10n/generated/app_localizations.dart';
import 'package:four3/src/app/locale_scope.dart';
import 'package:four3/src/common/theme/app_theme.dart';
import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/common/widget/app_controls.dart';
import 'package:four3/src/feature/settings/bloc/settings_bloc.dart';
import 'package:four3/src/feature/settings/model/app_settings.dart';
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
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '${(settings.volume * 100).round()}%',
                      style: const TextStyle(
                        color: AppColors.accent,
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
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 10,
                    ),
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
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        DropdownButton<Locale?>(
          value: scope.locale,
          underline: const SizedBox.shrink(),
          onChanged: scope.setLocale,
          items: [
            DropdownMenuItem(child: Text(l10n.systemLanguage)),
            DropdownMenuItem(
              value: const Locale('ru'),
              child: Text(l10n.languageRussian),
            ),
            DropdownMenuItem(
              value: const Locale('en'),
              child: Text(l10n.languageEnglish),
            ),
            DropdownMenuItem(
              value: const Locale('es'),
              child: Text(l10n.languageSpanish),
            ),
            DropdownMenuItem(
              value: const Locale('fr'),
              child: Text(l10n.languageFrench),
            ),
            DropdownMenuItem(
              value: const Locale.fromSubtags(
                languageCode: 'pt',
                countryCode: 'BR',
              ),
              child: Text(l10n.languagePortugueseBrazil),
            ),
            DropdownMenuItem(
              value: const Locale('de'),
              child: Text(l10n.languageGerman),
            ),
          ],
        ),
      ],
    );
  }
}

class _SettingRow extends StatelessWidget {
  const new({required this.icon, required this.child});

  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 54),
    padding: EdgeInsets.symmetric(
      vertical: MediaQuery.sizeOf(context).width <= 650 ? 10 : 18,
    ),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
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
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(color: AppColors.muted, fontSize: 10),
              ),
            ],
          ),
        ),
        AppToggle(value: value, onChanged: onChanged, semanticLabel: title),
      ],
    ),
  );
}
