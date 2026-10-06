import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:four3/src/common/theme/app_theme.dart';

enum AppSegmentedStyle { outlined, pill }

final class AppSegment<T> {
  const new({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

class AppToggle extends StatelessWidget {
  const new({
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    toggled: value,
    enabled: onChanged != null,
    button: true,
    child: InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        width: 48,
        height: 44,
        child: Center(
          child: AnimatedContainer(
            width: 40,
            height: 24,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: value ? AppColors.accent : const Color(0xFFD9DDCF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
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
            _item(options[index], pill: true)
          else
            Expanded(child: _item(options[index], pill: false)),
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

  Widget _item(AppSegment<T> option, {required bool pill}) {
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
                    color: active ? AppColors.accent : const Color(0xFFDCE0D4),
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
            style: TextStyle(
              color: active ? AppColors.accent : const Color(0xFF6A7165),
              fontFamily: 'Manrope',
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (option.icon case final icon?) ...[
                  Icon(
                    icon,
                    size: 16,
                    color: active ? AppColors.accent : const Color(0xFF6A7165),
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

class AppTextField extends StatelessWidget {
  const new({
    required this.controller,
    this.label,
    this.hintText,
    this.obscureText = false,
    this.autocorrect = true,
    this.autofocus = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.maxLength,
    this.inputFormatters,
    this.onSubmitted,
    this.fontSize = 16,
    this.letterSpacing,
    this.semanticLabel,
    super.key,
  });

  final TextEditingController controller;
  final String? label;
  final String? hintText;
  final bool obscureText;
  final bool autocorrect;
  final bool autofocus;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;
  final double fontSize;
  final double? letterSpacing;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (label case final value?) ...[
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
      ],
      Semantics(
        textField: true,
        label: semanticLabel ?? label,
        child: TextField(
          controller: controller,
          obscureText: obscureText,
          autocorrect: autocorrect,
          autofocus: autofocus,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          maxLength: maxLength,
          inputFormatters: inputFormatters,
          onSubmitted: onSubmitted,
          style: TextStyle(fontSize: fontSize, letterSpacing: letterSpacing),
          decoration: InputDecoration(
            hintText: hintText,
            counterText: '',
            isDense: true,
            contentPadding: const EdgeInsets.all(12),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(7),
              borderSide: const BorderSide(color: Color(0xFFDCE0D4)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(7),
              borderSide: const BorderSide(color: Color(0xFFDCE0D4)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(7),
              borderSide: const BorderSide(color: Color(0xFF8EA5F3)),
            ),
          ),
        ),
      ),
    ],
  );
}
