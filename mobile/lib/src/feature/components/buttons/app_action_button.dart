import 'package:flutter/material.dart';
import 'package:four3/src/feature/app_theme/utils/app_theme.dart';
import 'package:four3/src/feature/components/progress/app_circular_progress_indicator.dart';

enum AppActionStyle { primary, secondary, text, danger }

class AppActionButton extends StatelessWidget {
  const new({
    required this.label,
    required this.onPressed,
    this.style = AppActionStyle.primary,
    this.loading = false,
    this.leading,
    this.trailing,
    this.compact = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppActionStyle style;
  final bool loading;
  final Widget? leading;
  final Widget? trailing;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? effectiveOnPressed = loading ? null : onPressed;
    final Widget content = AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 160),
      child: loading
          ? Row(
              key: const ValueKey<String>('loading'),
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppCircularProgressIndicator(
                  dimension: 19,
                  color:
                      style == AppActionStyle.primary ||
                          style == AppActionStyle.danger
                      ? Colors.white
                      : AppColors.accent,
                ),
                const SizedBox(width: 10),
                Flexible(child: Text(label)),
              ],
            )
          : Row(
              key: const ValueKey<String>('content'),
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (leading case final widget?) ...[
                  widget,
                  const SizedBox(width: 10),
                ],
                Flexible(child: Text(label, textAlign: TextAlign.center)),
                if (trailing case final widget?) ...[
                  const SizedBox(width: 10),
                  widget,
                ],
              ],
            ),
    );
    final ButtonStyle minimum = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        Size(
          44,
          compact
              ? 44
              : style == AppActionStyle.primary
              ? 48
              : 48,
        ),
      ),
    );
    return switch (style) {
      AppActionStyle.primary => FilledButton(
        onPressed: effectiveOnPressed,
        style: minimum.copyWith(
          backgroundColor: loading
              ? const WidgetStatePropertyAll(AppColors.accent)
              : null,
          foregroundColor: loading
              ? const WidgetStatePropertyAll(Colors.white)
              : null,
        ),
        child: content,
      ),
      AppActionStyle.secondary => OutlinedButton(
        onPressed: effectiveOnPressed,
        style: minimum.copyWith(
          foregroundColor: loading
              ? const WidgetStatePropertyAll(AppColors.accent)
              : null,
          side: loading
              ? const WidgetStatePropertyAll(
                  BorderSide(color: AppColors.accent),
                )
              : null,
          backgroundColor: loading
              ? const WidgetStatePropertyAll(AppColors.accentSubtle)
              : null,
        ),
        child: content,
      ),
      AppActionStyle.text => TextButton(
        onPressed: effectiveOnPressed,
        style: minimum,
        child: content,
      ),
      AppActionStyle.danger => FilledButton(
        onPressed: effectiveOnPressed,
        style: minimum.copyWith(
          backgroundColor: const WidgetStatePropertyAll(AppColors.danger),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
        ),
        child: content,
      ),
    };
  }
}
