import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/feature/app_theme/utils/app_theme.dart';
import 'package:four3/src/feature/app_theme/utils/theme_context_extension.dart';
import 'package:four3/src/feature/components/progress/app_circular_progress_indicator.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AppTextField extends StatefulWidget {
  const new({
    required this.controller,
    this.label,
    this.hintText,
    this.helperText,
    this.errorText,
    this.obscureText = false,
    this.showPasswordToggle = false,
    this.autocorrect = true,
    this.autofocus = false,
    this.enabled = true,
    this.loading = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction,
    this.focusNode,
    this.autofillHints,
    this.maxLength,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.onEditingComplete,
    this.fontSize = 16,
    this.fontFamily,
    this.letterSpacing,
    this.semanticLabel,
    super.key,
  });

  final TextEditingController controller;
  final String? label;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final bool obscureText;
  final bool showPasswordToggle;
  final bool autocorrect;
  final bool autofocus;
  final bool enabled;
  final bool loading;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final Iterable<String>? autofillHints;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onEditingComplete;
  final double fontSize;
  final String? fontFamily;
  final double? letterSpacing;
  final String? semanticLabel;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _obscured = widget.obscureText;
  FocusNode? _ownedFocusNode;

  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode!;

  @override
  void initState() {
    super.initState();
    _attachFocusNode();
  }

  void _attachFocusNode() {
    if (widget.focusNode == null) _ownedFocusNode = FocusNode();
    _focusNode.addListener(_handleFocusChanged);
  }

  void _handleFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant AppTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.obscureText != widget.obscureText) {
      _obscured = widget.obscureText;
    }
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownedFocusNode)?.removeListener(
        _handleFocusChanged,
      );
      _ownedFocusNode?.dispose();
      _ownedFocusNode = null;
      _attachFocusNode();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasError = widget.errorText?.isNotEmpty ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.label case final value?) ...[
          Text(
            value,
            style: context.textStyle.bodyStrong.copyWith(fontSize: 12),
          ),
          const SizedBox(height: 8),
        ],
        Semantics(
          textField: true,
          liveRegion: hasError,
          label: widget.semanticLabel ?? widget.label,
          value: hasError ? widget.errorText : null,
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            obscureText: _obscured,
            autocorrect: widget.autocorrect,
            autofocus: widget.autofocus,
            enabled: widget.enabled && !widget.loading,
            keyboardType: widget.keyboardType,
            textCapitalization: widget.textCapitalization,
            textInputAction: widget.textInputAction,
            autofillHints: widget.autofillHints,
            maxLength: widget.maxLength,
            inputFormatters: widget.inputFormatters,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            onEditingComplete: widget.onEditingComplete,
            style: context.textStyle.body.copyWith(
              color: context.colors.ink,
              fontSize: widget.fontSize,
              fontFamily: widget.fontFamily,
              letterSpacing: widget.letterSpacing,
            ),
            decoration: InputDecoration(
              hintText: _focusNode.hasFocus ? null : widget.hintText,
              hintStyle: context.textStyle.body.copyWith(
                color: const Color(0xFF8B9088),
                fontSize: widget.fontSize,
                fontWeight: FontWeight.w400,
                fontFamily: widget.fontFamily,
                letterSpacing: widget.letterSpacing,
              ),
              counterText: '',
              isDense: true,
              constraints: const BoxConstraints(minHeight: 48),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 48,
                minHeight: 44,
              ),
              suffixIcon: widget.loading
                  ? const Center(
                      child: AppCircularProgressIndicator(dimension: 20),
                    )
                  : widget.showPasswordToggle
                  ? IconButton(
                      tooltip: _obscured
                          ? context.l10n.showPassword
                          : context.l10n.hidePassword,
                      onPressed: () => setState(() => _obscured = !_obscured),
                      icon: Icon(
                        _obscured ? LucideIcons.eye : LucideIcons.eyeOff,
                        size: 21,
                      ),
                    )
                  : null,
              filled: true,
              fillColor: widget.enabled
                  ? Colors.white
                  : context.colors.disabledSurface,
              border: _border(context.colors.controlBorder),
              enabledBorder: _border(
                hasError ? context.colors.danger : context.colors.controlBorder,
              ),
              focusedBorder: _border(
                hasError ? context.colors.danger : context.colors.accent,
                width: 1.5,
              ),
              disabledBorder: _border(context.colors.border),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Text(
            widget.errorText!,
            style: context.textStyle.caption.copyWith(
              color: context.colors.danger,
            ),
          ),
        ] else if (widget.helperText case final helper?) ...[
          const SizedBox(height: 6),
          Text(
            helper,
            style: context.textStyle.caption.copyWith(
              color: context.colors.muted,
            ),
          ),
        ],
      ],
    );
  }

  OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
        borderSide: BorderSide(color: color, width: width),
      );

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _ownedFocusNode?.dispose();
    super.dispose();
  }
}
