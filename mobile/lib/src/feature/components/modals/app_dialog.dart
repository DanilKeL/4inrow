import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/feature/app_theme/utils/theme_context_extension.dart';

typedef AppDialogBackBuilder = VoidCallback? Function(BuildContext context);

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required String Function(BuildContext context) titleBuilder,
  required WidgetBuilder builder,
  bool wide = false,
  Listenable? listenable,
  AppDialogBackBuilder? onBackBuilder,
}) => showGeneralDialog<T>(
  context: context,
  barrierDismissible: true,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  barrierColor: const Color(0x4D323A33),
  transitionBuilder: (context, animation, _, child) {
    final Animation<double> curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return AnimatedBuilder(
      animation: curved,
      child: FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: .985, end: 1).animate(curved),
          child: child,
        ),
      ),
      builder: (context, child) => BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 9 * curved.value,
          sigmaY: 9 * curved.value,
        ),
        child: child,
      ),
    );
  },
  pageBuilder: (context, _, _) => ListenableBuilder(
    listenable: listenable ?? const AlwaysStoppedAnimation<double>(1),
    builder: (context, _) => SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool shortLandscape =
              constraints.maxWidth >= 651 && constraints.maxHeight <= 550;
          final bool compact = constraints.maxWidth <= 650 || shortLandscape;
          final double inset = compact ? 10 : 24;
          final VoidCallback? onBack = onBackBuilder?.call(context);
          final String title = titleBuilder(context);
          return Center(
            child: Container(
              width: double.infinity,
              constraints: BoxConstraints(
                maxWidth: shortLandscape
                    ? 760
                    : wide
                    ? 800
                    : 480,
                maxHeight: constraints.maxHeight - inset * 2,
              ),
              margin: EdgeInsets.all(inset),
              padding: EdgeInsets.fromLTRB(
                compact ? 14 : 30,
                compact ? 14 : 24,
                compact ? 14 : 30,
                (compact ? 14 : 30) + MediaQuery.viewInsetsOf(context).bottom,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFBF7),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0x80FFFFFF)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x26162311),
                    blurRadius: 80,
                    offset: Offset(0, 24),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        AnimatedSize(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          child: onBack == null
                              ? const SizedBox.shrink()
                              : IconButton(
                                  tooltip: MaterialLocalizations.of(context)
                                      .backButtonTooltip,
                                  onPressed: onBack,
                                  icon: const Icon(
                                    Icons.arrow_back_rounded,
                                    size: 20,
                                  ),
                                ),
                        ),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            child: Align(
                              key: ValueKey<String>(title),
                              alignment: Alignment.centerLeft,
                              child: Text(
                                title,
                                style: context.textStyle.title.copyWith(
                                  fontSize: compact ? 21 : 23,
                                  letterSpacing: -.6,
                                ),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: context.l10n.close,
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded, size: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (wide)
                      Flexible(child: builder(context))
                    else
                      Flexible(
                        child: SingleChildScrollView(child: builder(context)),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  ),
);

class AppDialogPageTransition extends StatelessWidget {
  const new({
    required this.showSecond,
    required this.firstChild,
    required this.secondChild,
    super.key,
  });

  final bool showSecond;
  final Widget firstChild;
  final Widget secondChild;

  @override
  Widget build(BuildContext context) => AnimatedCrossFade(
    firstChild: firstChild,
    secondChild: secondChild,
    crossFadeState: showSecond
        ? CrossFadeState.showSecond
        : CrossFadeState.showFirst,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 260),
    firstCurve: Curves.easeInOutCubic,
    secondCurve: Curves.easeInOutCubic,
    sizeCurve: Curves.easeInOutCubic,
  );
}
