import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:four3/src/feature/app_theme/utils/theme_context_extension.dart';

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
          style: context.textStyle.captionStrong.copyWith(fontSize: 12),
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
          style: context.textStyle.body.copyWith(
            fontSize: fontSize,
            letterSpacing: letterSpacing,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            counterText: '',
            isDense: true,
            contentPadding: const EdgeInsets.all(12),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(7),
              borderSide: BorderSide(color: context.colors.controlBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(7),
              borderSide: BorderSide(color: context.colors.controlBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(7),
              borderSide: BorderSide(color: context.colors.accent),
            ),
          ),
        ),
      ),
    ],
  );
}
