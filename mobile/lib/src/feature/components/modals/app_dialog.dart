import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/feature/app_theme/utils/app_theme.dart';
import 'package:four3/src/feature/app_theme/utils/theme_context_extension.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

typedef AppDialogBackBuilder = VoidCallback? Function(BuildContext context);

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required String Function(BuildContext context) titleBuilder,
  required WidgetBuilder builder,
  bool wide = false,
  bool showCloseButton = true,
  bool barrierDismissible = true,
  VoidCallback? onDismiss,
  Listenable? listenable,
  AppDialogBackBuilder? onBackBuilder,
}) async {
  final FocusNode? previousFocus = FocusManager.instance.primaryFocus;
  final T? result = await showGeneralDialog<T>(
    context: context,
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180),
    barrierDismissible: barrierDismissible,
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
            scale: Tween<double>(begin: .99, end: 1).animate(curved),
            child: child,
          ),
        ),
        builder: (context, child) => BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 6 * curved.value,
            sigmaY: 6 * curved.value,
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
            final Duration motionDuration =
                MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180);
            final bool shortLandscape =
                constraints.maxWidth >= 651 && constraints.maxHeight <= 550;
            final bool compact = constraints.maxWidth <= 650 || shortLandscape;
            final double inset = compact ? 12 : 16;
            final bool needsConstrainedBody =
                MediaQuery.viewInsetsOf(context).bottom > 0 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.3;
            final VoidCallback? onBack = onBackBuilder?.call(context);
            final String title = titleBuilder(context);
            return PopScope(
              canPop: onBack == null,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) onBack?.call();
              },
              child: AnimatedPadding(
                duration: motionDuration,
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Center(
                  child: Container(
                    width: double.infinity,
                    constraints: BoxConstraints(
                      maxWidth: shortLandscape
                          ? 760
                          : wide
                          ? 800
                          : 480,
                      maxHeight: math.max(0, constraints.maxHeight - inset * 2),
                    ),
                    margin: EdgeInsets.all(inset),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAFBF7),
                      borderRadius: BorderRadius.circular(AppRadii.modal),
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
                        mainAxisSize: needsConstrainedBody
                            ? MainAxisSize.max
                            : MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              AnimatedSize(
                                duration: motionDuration,
                                curve: Curves.easeOutCubic,
                                child: onBack == null
                                    ? const SizedBox.shrink()
                                    : IconButton(
                                        tooltip: MaterialLocalizations.of(
                                          context,
                                        ).backButtonTooltip,
                                        onPressed: onBack,
                                        icon: const Icon(
                                          LucideIcons.arrowLeft,
                                          size: 21,
                                        ),
                                      ),
                              ),
                              Expanded(
                                child: AnimatedSwitcher(
                                  duration: motionDuration,
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  child: Align(
                                    key: ValueKey<String>(title),
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.textStyle.title.copyWith(
                                        fontSize: compact ? 21 : 23,
                                        height: 27 / 22,
                                        letterSpacing: -.4,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (showCloseButton)
                                IconButton(
                                  tooltip: context.l10n.close,
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(LucideIcons.x, size: 21),
                                ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          if (wide)
                            Flexible(
                              fit: needsConstrainedBody
                                  ? FlexFit.tight
                                  : FlexFit.loose,
                              child: builder(context),
                            )
                          else
                            Flexible(
                              fit: needsConstrainedBody
                                  ? FlexFit.tight
                                  : FlexFit.loose,
                              child: SingleChildScrollView(
                                child: builder(context),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  onDismiss?.call();
  if (previousFocus?.canRequestFocus ?? false) previousFocus!.requestFocus();
  return result;
}

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
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 260),
    reverseDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 260),
    firstCurve: Curves.easeInOutCubic,
    secondCurve: Curves.easeInOutCubic,
    sizeCurve: Curves.easeInOutCubic,
  );
}
