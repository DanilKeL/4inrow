import 'dart:ui';

import 'package:flutter/material.dart';

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required String title,
  required Widget child,
  bool wide = false,
}) => showGeneralDialog<T>(
  context: context,
  barrierDismissible: true,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  barrierColor: const Color(0x4D323A33),
  transitionDuration: const Duration(milliseconds: 150),
  transitionBuilder: (context, animation, _, child) => FadeTransition(
    opacity: animation,
    child: ScaleTransition(
      scale: Tween<double>(begin: .98, end: 1).animate(animation),
      child: child,
    ),
  ),
  pageBuilder: (context, _, _) => BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
    child: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool shortLandscape =
              constraints.maxWidth >= 651 && constraints.maxHeight <= 550;
          final bool compact = constraints.maxWidth <= 650 || shortLandscape;
          final double inset = compact ? 10 : 24;
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
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: compact ? 21 : 23,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.6,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Закрыть',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded, size: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (wide)
                      Flexible(child: child)
                    else
                      Flexible(child: SingleChildScrollView(child: child)),
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
