import 'package:flutter/material.dart';
import 'package:four3/src/feature/app_theme/utils/theme_context_extension.dart';

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
  Widget build(BuildContext context) {
    final Duration duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    return Semantics(
      label: semanticLabel,
      toggled: value,
      enabled: onChanged != null,
      button: true,
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          width: 51,
          height: 44,
          child: Center(
            child: AnimatedContainer(
              width: 51,
              height: 31,
              duration: duration,
              curve: Curves.easeOut,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: value
                    ? context.colors.accent
                    : context.colors.controlInactive,
                borderRadius: BorderRadius.circular(20),
              ),
              child: AnimatedAlign(
                duration: duration,
                curve: Curves.easeOut,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 25,
                  height: 25,
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
}
