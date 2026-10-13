import 'package:flutter/material.dart';

class AppCircularProgressIndicator extends StatelessWidget {
  const new({this.value, this.dimension = 28, this.color, super.key});

  final double? value;
  final double dimension;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: dimension,
    child: CircularProgressIndicator(
      value: value,
      backgroundColor: Colors.transparent,
      color: color ?? Theme.of(context).colorScheme.primary,
      strokeWidth: 2.5,
      strokeAlign: CircularProgressIndicator.strokeAlignInside,
      strokeCap: StrokeCap.round,
    ),
  );
}
