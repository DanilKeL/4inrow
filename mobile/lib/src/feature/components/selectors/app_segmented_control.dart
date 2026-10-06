import 'package:flutter/material.dart';
import 'package:four3/src/feature/app_theme/utils/theme_context_extension.dart';

enum AppSegmentedStyle { outlined, pill }

final class AppSegment<T> {
  const new({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

class AppSegmentedControl<T> extends StatelessWidget {
  const new({
    required this.options,
    required this.selected,
    required this.onChanged,
    this.style = AppSegmentedStyle.outlined,
    super.key,
  });

  final List<AppSegment<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final AppSegmentedStyle style;

  @override
  Widget build(BuildContext context) {
    final bool pill = style == AppSegmentedStyle.pill;
    final Widget row = Row(
      mainAxisSize: pill ? MainAxisSize.min : MainAxisSize.max,
      children: [
        for (var index = 0; index < options.length; index++) ...[
          if (index > 0) SizedBox(width: pill ? 5 : 7),
          if (pill)
            _AppSegmentItem<T>(
              option: options[index],
              selected: selected,
              pill: true,
              onChanged: onChanged,
            )
          else
            Expanded(
              child: _AppSegmentItem<T>(
                option: options[index],
                selected: selected,
                pill: false,
                onChanged: onChanged,
              ),
            ),
        ],
      ],
    );
    if (!pill) return row;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F2EC),
          border: Border.all(color: const Color(0xFFDFE3D9)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: row,
      ),
    );
  }
}

class _AppSegmentItem<T> extends StatelessWidget {
  const new({
    required this.option,
    required this.selected,
    required this.pill,
    required this.onChanged,
  });

  final AppSegment<T> option;
  final T selected;
  final bool pill;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final bool active = option.value == selected;
    return Semantics(
      selected: active,
      button: true,
      child: InkWell(
        onTap: () => onChanged(option.value),
        borderRadius: BorderRadius.circular(7),
        child: AnimatedContainer(
          constraints: const BoxConstraints(minHeight: 44),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(
            horizontal: pill ? 14 : 8,
            vertical: pill ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: active
                ? (pill ? Colors.white : const Color(0xFFE8EDFE))
                : (pill ? Colors.transparent : Colors.white),
            border: pill
                ? null
                : Border.all(
                    color: active
                        ? context.colors.accent
                        : context.colors.controlBorder,
                  ),
            borderRadius: BorderRadius.circular(7),
            boxShadow: active && pill
                ? const [
                    BoxShadow(
                      color: Color(0x1226351A),
                      blurRadius: 10,
                      offset: Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            style: context.textStyle.captionStrong.copyWith(
              color: active ? context.colors.accent : context.colors.muted,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (option.icon case final icon?) ...[
                  Icon(
                    icon,
                    size: 16,
                    color: active
                        ? context.colors.accent
                        : context.colors.muted,
                  ),
                  const SizedBox(width: 7),
                ],
                Flexible(
                  child: Text(option.label, textAlign: TextAlign.center),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
