import 'package:flutter/material.dart';

class AppCircularProgressIndicator extends StatelessWidget {
  const new({this.value, super.key});

  final double? value;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 28,
    child: CircularProgressIndicator(
      value: value,
      backgroundColor: Colors.transparent,
      color: Theme.of(context).colorScheme.primary,
      strokeWidth: 2.5,
      strokeAlign: CircularProgressIndicator.strokeAlignInside,
      strokeCap: StrokeCap.round,
    ),
  );
}
