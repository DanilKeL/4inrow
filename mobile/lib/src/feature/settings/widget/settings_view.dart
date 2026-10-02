import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:four3/src/common/theme/app_theme.dart';
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
        void update(AppSettings value) => bloc.add(SettingsEvent$Update(value));
        final items = <Widget>[
          _SettingRow(
            icon: LucideIcons.volume2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Громкость звуков',
                        style: TextStyle(
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
                  const Text(
                    'Звук выключен кнопкой в шапке',
                    style: TextStyle(color: AppColors.muted, fontSize: 10),
                  ),
              ],
            ),
          ),
          _SettingSwitch(
            icon: LucideIcons.sparkles,
            value: settings.animations,
            title: 'Анимации',
            subtitle: 'Падение фишек и плавная камера',
            onChanged: (value) => update(settings.copyWith(animations: value)),
          ),
          _SettingSwitch(
            icon: LucideIcons.mousePointer2,
            value: settings.hints,
            title: 'Предпросмотр хода',
            subtitle: 'Показывать фишку при наведении',
            onChanged: (value) => update(settings.copyWith(hints: value)),
          ),
          _SettingSwitch(
            icon: LucideIcons.scanLine,
            value: settings.xrayDefault,
            title: 'Рентген по умолчанию',
            subtitle: 'Прозрачные фишки в новой партии',
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
