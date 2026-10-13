import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:four3/src/feature/appearance/data/skin_image_cache.dart';
import 'package:four3/src/feature/appearance/domain/model/skin_catalog.dart';

final class SkinArtwork {
  const new(this.images, {this.metallicRoughness});

  final Map<SkinSurface, ui.Image> images;
  final ui.Image? metallicRoughness;

  ui.Image operator [](SkinSurface surface) => images[surface]!;

  void dispose() {
    for (final ui.Image image in images.values) {
      image.dispose();
    }
    metallicRoughness?.dispose();
  }
}

final class SkinTexturePainter {
  const new(this.imageCache);

  final SkinImageCache imageCache;

  Future<SkinArtwork?> paint(Skin skin, {bool preloadImages = true}) async {
    if (skin.design == null && skin.artwork == 'nocturne') {
      return _paintNocturne(skin.palette);
    }
    final SkinDesign? design = skin.design;
    if (design == null) return null;
    if (preloadImages) await imageCache.preload(design.imageIds);
    final result = <SkinSurface, ui.Image>{};
    try {
      for (final SkinSurface surface in SkinSurface.values) {
        final String background = switch (surface) {
          SkinSurface.board => skin.palette.board.body,
          SkinSurface.darkCap => skin.palette.dark.cap,
          SkinSurface.darkBody => skin.palette.dark.body,
          SkinSurface.lightCap => skin.palette.light.cap,
          SkinSurface.lightBody => skin.palette.light.body,
        };
        result[surface] = await _surface(surface, background, design[surface]);
      }
    } on Object {
      for (final ui.Image image in result.values) {
        image.dispose();
      }
      rethrow;
    }
    return SkinArtwork(Map.unmodifiable(result));
  }

  Future<ui.Image> _surface(
    SkinSurface surface,
    String background,
    SurfaceDesign design,
  ) async {
    final width = surface == SkinSurface.board ? 1024 : 512;
    final height = surface.name.endsWith('Body') ? 256 : width;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final size = ui.Size(width.toDouble(), height.toDouble());
    canvas.drawRect(
      ui.Offset.zero & size,
      ui.Paint()..color = color(background),
    );
    if (design.decorated || design.border) {
      canvas.drawRect(
        ui.Offset.zero & size,
        ui.Paint()
          ..shader = ui.Gradient.linear(
            ui.Offset.zero,
            ui.Offset(width.toDouble(), height.toDouble()),
            const [
              ui.Color(0x0BFFFFFF),
              ui.Color(0x00FFFFFF),
              ui.Color(0x17000000),
            ],
            const [0, .5, 1],
          ),
      );
    }
    final patternPaint = ui.Paint()
      ..color = color(design.ink).withValues(alpha: design.patternOpacity)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = math.max(.85, math.min(width, height) * .0018);
    switch (design.pattern) {
      case SkinPattern.none:
        break;
      case SkinPattern.celestial:
        _celestial(canvas, size, design.patternScale, surface, patternPaint);
        break;
      case SkinPattern.botanical:
        _botanical(canvas, size, design.patternScale, patternPaint);
        break;
      case SkinPattern.artdeco:
        _artDeco(canvas, size, design.patternScale, patternPaint);
        break;
      case SkinPattern.guilloche:
        _guilloche(canvas, size, design.patternScale, patternPaint);
        break;
      case SkinPattern.marble:
        _marble(canvas, size, design.patternScale, patternPaint);
        break;
      case SkinPattern.gingham:
        _gingham(canvas, size, design.patternScale, patternPaint);
        break;
      case SkinPattern.sakuraWaves:
        _sakuraWaves(canvas, size, design.patternScale, surface, patternPaint);
        break;
    }
    if (design.border) _border(canvas, size, surface, color(design.ink));
    _layers(canvas, size, design.layers);
    return recorder.endRecording().toImage(width, height);
  }

  void _circle(
    ui.Canvas canvas,
    ui.Offset center,
    double radius,
    ui.Paint paint,
  ) =>
      canvas.drawCircle(center, radius, paint..style = ui.PaintingStyle.stroke);

  void _star(
    ui.Canvas canvas,
    ui.Offset center,
    double radius,
    ui.Paint paint,
  ) {
    final path = ui.Path()
      ..moveTo(center.dx, center.dy - radius)
      ..quadraticBezierTo(
        center.dx + radius * .2,
        center.dy - radius * .2,
        center.dx + radius,
        center.dy,
      )
      ..quadraticBezierTo(
        center.dx + radius * .2,
        center.dy + radius * .2,
        center.dx,
        center.dy + radius,
      )
      ..quadraticBezierTo(
        center.dx - radius * .2,
        center.dy + radius * .2,
        center.dx - radius,
        center.dy,
      )
      ..quadraticBezierTo(
        center.dx - radius * .2,
        center.dy - radius * .2,
        center.dx,
        center.dy - radius,
      )
      ..close();
    canvas.drawPath(path, paint..style = ui.PaintingStyle.fill);
  }

  void _rosette(ui.Canvas canvas, double radius, int petals, ui.Paint paint) {
    for (var index = 0; index < petals; index++) {
      canvas.save();
      canvas.rotate(index * math.pi * 2 / petals);
      final path = ui.Path()
        ..moveTo(0, 0)
        ..cubicTo(
          -radius * .3,
          -radius * .4,
          -radius * .3,
          -radius * .78,
          0,
          -radius,
        )
        ..cubicTo(radius * .3, -radius * .78, radius * .3, -radius * .4, 0, 0);
      canvas.drawPath(path, paint..style = ui.PaintingStyle.stroke);
      canvas.restore();
    }
  }

  void _branch(ui.Canvas canvas, double length, double bend, ui.Paint paint) {
    final stem = ui.Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(length * .5, bend, length, 0);
    canvas.drawPath(stem, paint..style = ui.PaintingStyle.stroke);
    for (var index = 1; index < 9; index++) {
      final double ratio = index / 10;
      final double x = length * ratio;
      final double y = 2 * ratio * (1 - ratio) * bend;
      for (final side in const [-1, 1]) {
        final leaf = ui.Path()
          ..moveTo(x, y)
          ..cubicTo(
            x + length * .06,
            y + side * length * .03,
            x + length * .08,
            y + side * length * .13,
            x + length * .13,
            y + side * length * .16,
          )
          ..cubicTo(
            x + length * .03,
            y + side * length * .17,
            x - length * .03,
            y + side * length * .06,
            x,
            y,
          );
        canvas.drawPath(leaf, paint..style = ui.PaintingStyle.stroke);
      }
    }
  }

  void _motif(ui.Canvas canvas, SkinMotif motif, double size, ui.Paint paint) {
    final double r = size / 2;
    paint.strokeWidth = math.max(1, size * .009);
    switch (motif) {
      case SkinMotif.heart:
        final path = ui.Path()
          ..moveTo(0, r * .82)
          ..cubicTo(-r * .28, r * .51, -r * .92, r * .12, -r * .86, -r * .35)
          ..cubicTo(-r * .8, -r * .91, -r * .22, -r * .97, 0, -r * .51)
          ..cubicTo(r * .22, -r * .97, r * .8, -r * .91, r * .86, -r * .35)
          ..cubicTo(r * .92, r * .12, r * .28, r * .51, 0, r * .82)
          ..close();
        canvas.drawPath(path, paint..style = ui.PaintingStyle.fill);
        break;
      case SkinMotif.bow:
        for (final side in const [-1, 1]) {
          canvas.save();
          canvas.scale(side.toDouble(), 1);
          final loop = ui.Path()
            ..moveTo(0, 0)
            ..cubicTo(r * .35, -r * .52, r * .96, -r * .7, r * .92, -r * .32)
            ..cubicTo(r * .9, r * .2, r * .52, r * .32, 0, 0)
            ..close();
          final tail = ui.Path()
            ..moveTo(r * .02, r * .01)
            ..lineTo(r * .61, r * .76)
            ..lineTo(r * .61, r * .42)
            ..lineTo(r * .34, r * .52)
            ..lineTo(-r * .06, r * .07)
            ..close();
          canvas.drawPath(loop, paint..style = ui.PaintingStyle.fill);
          canvas.drawPath(tail, paint);
          canvas.restore();
        }
        canvas.drawOval(
          ui.Rect.fromCenter(
            center: ui.Offset.zero,
            width: r * .38,
            height: r * .46,
          ),
          paint,
        );
        break;
      case SkinMotif.blossom:
        for (var petal = 0; petal < 6; petal++) {
          canvas.save();
          canvas.rotate(petal * math.pi / 3);
          canvas.drawOval(
            ui.Rect.fromCenter(
              center: ui.Offset(0, -r * .52),
              width: r * .56,
              height: r * .88,
            ),
            paint..style = ui.PaintingStyle.fill,
          );
          canvas.restore();
        }
        canvas.drawCircle(
          ui.Offset.zero,
          r * .23,
          ui.Paint()..color = const ui.Color(0xFFE7BF7D),
        );
        break;
      case SkinMotif.sakura:
        _sakuraFlower(canvas, r * .96, paint);
        break;
      case SkinMotif.kitsune:
        _kitsuneMask(canvas, r * .97, paint);
        break;
      case SkinMotif.crest:
        _lunarCrest(canvas, r, paint);
        break;
      case SkinMotif.star:
        _star(canvas, ui.Offset.zero, r * .85, paint);
        _circle(canvas, ui.Offset.zero, r * .97, paint);
        break;
      case SkinMotif.moon:
        final moon = ui.Path()
          ..moveTo(r * .35, -r * .78)
          ..cubicTo(-r * .8, -r * .98, -r, r * .75, r * .1, r * .9)
          ..cubicTo(-r * .35, r * .3, -r * .24, -r * .47, r * .35, -r * .78)
          ..close();
        canvas.drawPath(moon, paint..style = ui.PaintingStyle.fill);
        _circle(canvas, ui.Offset.zero, r * .98, paint);
        _star(canvas, ui.Offset(r * .6, -r * .03), r * .22, paint);
        _star(canvas, ui.Offset(r * .39, r * .49), r * .075, paint);
        _star(canvas, ui.Offset(r * .45, -r * .55), r * .075, paint);
        break;
      case SkinMotif.sun:
        _rosette(canvas, r * .65, 12, paint);
        _circle(canvas, ui.Offset.zero, r * .3, paint);
        _circle(canvas, ui.Offset.zero, r * .25, paint);
        _star(canvas, ui.Offset.zero, r * .16, paint);
        for (var index = 0; index < 32; index++) {
          final double angle = index * math.pi / 16;
          canvas.drawLine(
            ui.Offset(math.cos(angle) * r * .73, math.sin(angle) * r * .73),
            ui.Offset(
              math.cos(angle) * r * (index.isOdd ? .84 : .98),
              math.sin(angle) * r * (index.isOdd ? .84 : .98),
            ),
            paint,
          );
        }
        break;
      case SkinMotif.lotus:
        _rosette(canvas, r * .93, 8, paint);
        canvas.save();
        canvas.rotate(math.pi / 8);
        _rosette(canvas, r * .72, 8, paint);
        canvas.restore();
        _circle(canvas, ui.Offset.zero, r * .17, paint);
        break;
      case SkinMotif.laurel:
        for (final side in const [-1, 1]) {
          canvas.save();
          canvas.scale(side.toDouble(), 1);
          canvas.rotate(-math.pi * .38);
          canvas.translate(-r * .72, r * .05);
          _branch(canvas, r * 1.42, -r * .62, paint);
          canvas.restore();
        }
        _star(canvas, ui.Offset(0, -r * .62), r * .09, paint);
        break;
      case SkinMotif.diamond:
        for (final extent in const [.95, .7, .29]) {
          final diamond = ui.Path()
            ..moveTo(0, -r * extent)
            ..lineTo(r * extent, 0)
            ..lineTo(0, r * extent)
            ..lineTo(-r * extent, 0)
            ..close();
          canvas.drawPath(diamond, paint..style = ui.PaintingStyle.stroke);
        }
        _star(canvas, ui.Offset.zero, r * .15, paint);
        break;
      case SkinMotif.rings:
        for (final extent in const [.97, .82, .6, .31]) {
          _circle(canvas, ui.Offset.zero, r * extent, paint);
        }
        for (var index = 0; index < 48; index++) {
          final double angle = index * math.pi / 24;
          canvas.drawLine(
            ui.Offset(math.cos(angle) * r * .87, math.sin(angle) * r * .87),
            ui.Offset(
              math.cos(angle) * r * (index % 4 == 0 ? .97 : .92),
              math.sin(angle) * r * (index % 4 == 0 ? .97 : .92),
            ),
            paint,
          );
        }
        break;
    }
  }

  ui.Path _sakuraPetal(double radius) => ui.Path()
    ..moveTo(0, radius * .08)
    ..cubicTo(
      -radius * .42,
      -radius * .23,
      -radius * .41,
      -radius * .73,
      -radius * .12,
      -radius,
    )
    ..quadraticBezierTo(-radius * .04, -radius * .96, 0, -radius * .81)
    ..quadraticBezierTo(radius * .04, -radius * .96, radius * .12, -radius)
    ..cubicTo(
      radius * .41,
      -radius * .73,
      radius * .42,
      -radius * .23,
      0,
      radius * .08,
    )
    ..close();

  void _sakuraFlower(ui.Canvas canvas, double radius, ui.Paint source) {
    for (var petal = 0; petal < 5; petal++) {
      canvas.save();
      canvas.rotate(petal * math.pi * 2 / 5);
      canvas.drawPath(
        _sakuraPetal(radius),
        ui.Paint()
          ..color = source.color
          ..style = ui.PaintingStyle.fill,
      );
      canvas.drawPath(
        _sakuraPetal(radius),
        ui.Paint()
          ..color = const ui.Color(0x8FFFE5E1)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = math.max(.5, radius * .014),
      );
      canvas.restore();
    }
    canvas.drawCircle(
      ui.Offset.zero,
      radius * .105,
      ui.Paint()..color = const ui.Color(0xFFF3DDD4),
    );
  }

  void _kitsuneMask(ui.Canvas canvas, double r, ui.Paint source) {
    final mask = ui.Path()
      ..moveTo(0, -r * .61)
      ..cubicTo(-r * .21, -r * .65, -r * .35, -r * .56, -r * .45, -r * .5)
      ..lineTo(-r * .82, -r * .98)
      ..quadraticBezierTo(-r * .98, -r * .39, -r * .88, -r * .1)
      ..cubicTo(-r * .95, r * .22, -r * .67, r * .54, -r * .42, r * .67)
      ..cubicTo(-r * .22, r * .85, -r * .15, r * .87, 0, r * .95)
      ..cubicTo(r * .15, r * .87, r * .22, r * .85, r * .42, r * .67)
      ..cubicTo(r * .67, r * .54, r * .95, r * .22, r * .88, -r * .1)
      ..quadraticBezierTo(r * .98, -r * .39, r * .82, -r * .98)
      ..lineTo(r * .45, -r * .5)
      ..cubicTo(r * .35, -r * .56, r * .21, -r * .65, 0, -r * .61)
      ..close();
    canvas.drawPath(mask, source..style = ui.PaintingStyle.fill);
    for (final side in const [-1, 1]) {
      final eye = ui.Path()
        ..moveTo(side * r * .13, -r * .07)
        ..quadraticBezierTo(side * r * .43, -r * .3, side * r * .73, -r * .12)
        ..quadraticBezierTo(side * r * .46, r * .12, side * r * .13, -r * .07)
        ..close();
      canvas.drawPath(eye, ui.Paint()..color = const ui.Color(0xFF182843));
    }
    final nose = ui.Path()
      ..moveTo(-r * .13, r * .48)
      ..quadraticBezierTo(0, r * .42, r * .13, r * .48)
      ..quadraticBezierTo(r * .075, r * .6, 0, r * .63)
      ..quadraticBezierTo(-r * .075, r * .6, -r * .13, r * .48)
      ..close();
    canvas.drawPath(nose, ui.Paint()..color = const ui.Color(0xFF182843));
  }

  void _lunarCrest(ui.Canvas canvas, double r, ui.Paint paint) {
    for (final extent in const [.93, .87, .55]) {
      _circle(canvas, ui.Offset.zero, r * extent, paint);
    }
    for (var index = 0; index < 16; index++) {
      final double angle = index * math.pi / 8;
      canvas.drawLine(
        ui.Offset(math.cos(angle) * r * .8, math.sin(angle) * r * .8),
        ui.Offset(
          math.cos(angle) * r * (index % 4 == 0 ? .72 : .84),
          math.sin(angle) * r * (index % 4 == 0 ? .72 : .84),
        ),
        paint,
      );
    }
    final moon = ui.Path()
      ..moveTo(r * .15, -r * .43)
      ..cubicTo(-r * .56, -r * .53, -r * .65, r * .4, -r * .01, r * .47)
      ..cubicTo(-r * .26, r * .14, -r * .19, -r * .24, r * .15, -r * .43)
      ..close();
    canvas.drawPath(moon, paint..style = ui.PaintingStyle.fill);
    _star(canvas, ui.Offset(r * .26, r * .01), r * .145, paint);
  }

  void _celestial(
    ui.Canvas canvas,
    ui.Size size,
    double scale,
    SkinSurface surface,
    ui.Paint paint,
  ) {
    final double s = math.min(size.width, size.height);
    final ui.Offset center = size.center(ui.Offset.zero);
    for (final radius in const [.17, .3, .43]) {
      _circle(canvas, center, s * radius / scale, paint);
    }
    for (final angle in const [-.54, .7]) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      canvas.drawOval(
        ui.Rect.fromCenter(
          center: ui.Offset.zero,
          width: s * .92 / scale,
          height: s * .32 / scale,
        ),
        paint..style = ui.PaintingStyle.stroke,
      );
      canvas.restore();
    }
    for (var index = 0; index < 72; index++) {
      final double angle = index * math.pi / 36;
      canvas.drawLine(
        center +
            ui.Offset(
              math.cos(angle) * s * .425 / scale,
              math.sin(angle) * s * .425 / scale,
            ),
        center +
            ui.Offset(
              math.cos(angle) * s * (index % 6 == 0 ? .403 : .418) / scale,
              math.sin(angle) * s * (index % 6 == 0 ? .403 : .418) / scale,
            ),
        paint,
      );
    }
    var seed = 34123;
    double random() {
      seed = (seed * 1664525 + 1013904223) & 0xffffffff;
      return seed / 4294967296;
    }

    for (var index = 0; index < 48 * scale; index++) {
      _star(
        canvas,
        ui.Offset(random() * size.width, random() * size.height),
        s * (index % 7 == 0 ? .005 : .0018),
        paint,
      );
    }
    const points = [
      [.23, .11],
      [.38, .25],
      [.57, .2],
      [.79, .35],
      [.84, .57],
      [.67, .78],
      [.36, .84],
      [.15, .64],
    ];
    final path = ui.Path();
    for (var index = 0; index < points.length; index++) {
      final point = ui.Offset(
        points[index][0] * size.width,
        points[index][1] * size.height,
      );
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
      _star(canvas, point, s * .006, paint);
    }
    canvas.drawPath(path, paint..style = ui.PaintingStyle.stroke);
    if (surface == SkinSurface.board) {
      final ui.Paint sealPaint = ui.Paint()
        ..color = paint.color.withValues(alpha: paint.color.a * .6)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = paint.strokeWidth;
      for (var y = 0; y < 5; y++) {
        for (var x = 0; x < 5; x++) {
          final point = ui.Offset(
            size.width / 2 + ((x - 2) * 1.09 / 6.09) * size.width,
            size.height / 2 + ((y - 2) * 1.09 / 6.09) * size.height,
          );
          _circle(canvas, point, s * .053, sealPaint);
          _circle(canvas, point, s * .049, sealPaint);
          canvas.save();
          canvas.translate(point.dx, point.dy);
          _rosette(canvas, s * .028, (x + y).isOdd ? 8 : 12, sealPaint);
          canvas.restore();
        }
      }
    }
  }

  void _botanical(
    ui.Canvas canvas,
    ui.Size size,
    double scale,
    ui.Paint paint,
  ) {
    final double step = math.min(size.width, size.height) * .34 / scale;
    for (double y = -step; y < size.height + step; y += step) {
      for (double x = -step; x < size.width + step; x += step) {
        canvas.save();
        canvas.translate(x + ((y / step).round().isOdd ? step / 2 : 0), y);
        canvas.rotate(-math.pi / 4);
        _branch(canvas, step * .97, -step * .13, paint);
        canvas.restore();
      }
    }
  }

  void _artDeco(ui.Canvas canvas, ui.Size size, double scale, ui.Paint paint) {
    final double step = math.min(size.width, size.height) * .24 / scale;
    for (double y = -step; y < size.height + step; y += step * .7) {
      for (double x = -step; x < size.width + step; x += step) {
        final center = ui.Offset(
          x + ((y / (step * .7)).round().isOdd ? step / 2 : 0),
          y,
        );
        for (final double radius in [
          .32,
          .41,
          .48,
        ].map((value) => value * step)) {
          canvas.drawArc(
            ui.Rect.fromCircle(center: center, radius: radius),
            math.pi,
            math.pi,
            false,
            paint..style = ui.PaintingStyle.stroke,
          );
        }
        for (var index = 1; index < 12; index++) {
          final double angle = math.pi + index / 12 * math.pi;
          canvas.drawLine(
            center +
                ui.Offset(
                  math.cos(angle) * step * .32,
                  math.sin(angle) * step * .32,
                ),
            center +
                ui.Offset(
                  math.cos(angle) * step * .48,
                  math.sin(angle) * step * .48,
                ),
            paint,
          );
        }
        final ui.Path base = ui.Path()
          ..moveTo(center.dx - step * .48, center.dy)
          ..lineTo(center.dx, center.dy + step * .24)
          ..lineTo(center.dx + step * .48, center.dy);
        canvas.drawPath(base, paint..style = ui.PaintingStyle.stroke);
      }
    }
  }

  void _gingham(ui.Canvas canvas, ui.Size size, double scale, ui.Paint paint) {
    final double step = math.min(size.width, size.height) * .12 / scale;
    final ui.Paint fill = ui.Paint()
      ..color = paint.color.withValues(alpha: paint.color.a * .6)
      ..style = ui.PaintingStyle.fill;
    for (double x = 0; x < size.width; x += step * 2) {
      canvas.drawRect(ui.Rect.fromLTWH(x, 0, step, size.height), fill);
    }
    for (double y = 0; y < size.height; y += step * 2) {
      canvas.drawRect(ui.Rect.fromLTWH(0, y, size.width, step), fill);
    }
  }

  void _sakuraSprig(ui.Canvas canvas, double length, ui.Paint source) {
    final ui.Path limb = ui.Path()
      ..moveTo(0, 0)
      ..cubicTo(
        length * .25,
        -length * .04,
        length * .6,
        -length * .04,
        length,
        -length * .14,
      )
      ..moveTo(length * .24, -length * .025)
      ..quadraticBezierTo(
        length * .3,
        -length * .17,
        length * .43,
        -length * .23,
      )
      ..moveTo(length * .5, -length * .045)
      ..quadraticBezierTo(length * .65, length * .1, length * .83, length * .11)
      ..moveTo(length * .68, -length * .075)
      ..quadraticBezierTo(
        length * .72,
        -length * .21,
        length * .79,
        -length * .29,
      )
      ..moveTo(length * .86, -length * .1)
      ..quadraticBezierTo(
        length * .91,
        -length * .015,
        length * .99,
        length * .04,
      );
    canvas.drawPath(
      limb,
      ui.Paint()
        ..color = const ui.Color(0xB3BFBDCD)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = math.max(.7, length * .0033),
    );
    const flowers = <(double, double, double)>[
      (.43, -.23, .059),
      (.36, -.19, .033),
      (.79, -.29, .052),
      (.73, -.22, .034),
      (.83, .11, .062),
      (.74, .085, .035),
      (.99, .04, .046),
      (1, -.14, .039),
    ];
    for (var index = 0; index < flowers.length; index++) {
      final (double, double, double) flower = flowers[index];
      canvas.save();
      canvas.translate(flower.$1 * length, flower.$2 * length);
      canvas.rotate(index * 1.17);
      _sakuraFlower(
        canvas,
        flower.$3 * length,
        ui.Paint()
          ..color = index % 3 == 0
              ? const ui.Color(0xFFF0BEB8)
              : const ui.Color(0xFFEF9B9E),
      );
      canvas.restore();
    }
  }

  void _sakuraWaves(
    ui.Canvas canvas,
    ui.Size size,
    double scale,
    SkinSurface surface,
    ui.Paint source,
  ) {
    final double s = math.min(size.width, size.height);
    final bool body = surface.name.endsWith('Body');
    final int bands = ((body ? 2.5 : 4.5) * scale).round().clamp(3, 8);
    for (var band = 0; band < bands; band++) {
      for (final double offset in const [0, .01, .023]) {
        final double y =
            (-.16 + band * 1.32 / (bands - 1) + offset) * size.height;
        final ui.Path path = ui.Path()
          ..moveTo(-size.width * .08, y + size.height * .13)
          ..cubicTo(
            size.width * .14,
            y + size.height * .12,
            size.width * .25,
            y - size.height * .12,
            size.width * .46,
            y - size.height * .025,
          )
          ..cubicTo(
            size.width * .67,
            y + size.height * .15,
            size.width * .86,
            y + size.height * .06,
            size.width * 1.08,
            y - size.height * .11,
          );
        canvas.drawPath(
          path,
          ui.Paint()
            ..color = source.color.withValues(
              alpha:
                  source.color.a *
                  (body
                      ? .24
                      : offset == 0
                      ? .46
                      : .25),
            )
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = math.max(.65, s * (offset == 0 ? .00115 : .0008))
            ..strokeCap = ui.StrokeCap.round
            ..strokeJoin = ui.StrokeJoin.round,
        );
      }
    }
    if (surface == SkinSurface.board) {
      for (final sprig in const <(double, double, double)>[
        (-.02, .175, -.2),
        (1.02, .825, math.pi - .2),
      ]) {
        canvas.save();
        canvas.translate(sprig.$1 * size.width, sprig.$2 * size.height);
        canvas.rotate(sprig.$3);
        _sakuraSprig(canvas, s * .39 / math.sqrt(scale), source);
        canvas.restore();
      }
    } else if (!body) {
      canvas.save();
      canvas.translate(size.width * .19, size.height * .78);
      canvas.rotate(-.36);
      _sakuraSprig(canvas, s * .55 / math.sqrt(scale), source);
      canvas.restore();
    }
    final List<(double, double)> petals = body
        ? const [(.16, .32), (.51, .68), (.85, .29)]
        : const [
            (.17, .4),
            (.1, .69),
            (.42, .11),
            (.68, .075),
            (.9, .37),
            (.87, .59),
            (.56, .87),
            (.31, .94),
          ];
    for (var index = 0; index < petals.length; index++) {
      canvas.save();
      canvas.translate(
        petals[index].$1 * size.width,
        petals[index].$2 * size.height,
      );
      canvas.rotate(index * 1.31 + .4);
      canvas.scale(.7, 1);
      canvas.drawPath(
        _sakuraPetal(s * (index.isOdd ? .012 : .016) / math.sqrt(scale)),
        ui.Paint()
          ..color =
              (index % 3 == 0
                      ? const ui.Color(0xFFD8CBD7)
                      : const ui.Color(0xFFED939F))
                  .withValues(alpha: body ? .3 : .57),
      );
      canvas.restore();
    }
  }

  void _guilloche(
    ui.Canvas canvas,
    ui.Size size,
    double scale,
    ui.Paint paint,
  ) {
    final double s = math.min(size.width, size.height);
    final ui.Offset center = size.center(ui.Offset.zero);
    for (var wave = 0; wave < 12; wave++) {
      final path = ui.Path();
      for (var index = 0; index <= 720; index++) {
        final double angle = index / 720 * math.pi * 2;
        final double radius =
            s *
            (.3 +
                math.sin(angle * (9 + (scale * 2).round()) + wave * .18) * .11 +
                wave * .003);
        final ui.Offset point =
            center +
            ui.Offset(math.cos(angle) * radius, math.sin(angle) * radius);
        if (index == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, paint..style = ui.PaintingStyle.stroke);
    }
    _circle(canvas, center, s * .19, paint);
    _circle(canvas, center, s * .185, paint);
  }

  void _marble(ui.Canvas canvas, ui.Size size, double scale, ui.Paint paint) {
    var seed = 91783;
    double random() {
      seed = (seed * 1664525 + 1013904223) & 0xffffffff;
      return seed / 4294967296;
    }

    for (var line = -4; line < 12 * scale; line++) {
      final double start = line * size.height / (9 * scale);
      final double phase = random() * math.pi * 2;
      final path = ui.Path();
      for (double x = -30; x <= size.width + 30; x += 8) {
        final double y =
            start +
            math.sin(x / size.width * 6 + phase) * size.height * .08 +
            math.sin(x / size.width * 21 + phase * 2) * size.height * .016 +
            x * .18;
        if (x == -30) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      for (final ({double alpha, double width}) stroke in [
        (alpha: .065, width: size.height * .07),
        (alpha: .2, width: size.height * .01),
        (alpha: .8, width: math.max(.75, size.height * .0015)),
      ]) {
        canvas.drawPath(
          path,
          ui.Paint()
            ..color = paint.color.withValues(
              alpha: paint.color.a * stroke.alpha,
            )
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = stroke.width,
        );
      }
    }
  }

  void _border(
    ui.Canvas canvas,
    ui.Size size,
    SkinSurface surface,
    ui.Color ink,
  ) {
    final paint = ui.Paint()
      ..color = ink
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = math.max(1.25, size.width * .0019);
    if (surface.name.endsWith('Cap')) {
      _circle(canvas, size.center(ui.Offset.zero), size.width * .435, paint);
      _circle(canvas, size.center(ui.Offset.zero), size.width * .41, paint);
      final ui.Offset center = size.center(ui.Offset.zero);
      for (var index = 0; index < 48; index++) {
        final double angle = index * math.pi / 24;
        _star(
          canvas,
          center +
              ui.Offset(
                math.cos(angle) * size.width * .425,
                math.sin(angle) * size.width * .425,
              ),
          index % 4 == 0 ? 2.5 : 1,
          paint,
        );
      }
    } else if (surface.name.endsWith('Body')) {
      for (final double y in [
        .12,
        .16,
        .84,
        .88,
      ].map((value) => value * size.height)) {
        canvas.drawLine(ui.Offset(0, y), ui.Offset(size.width, y), paint);
      }
    } else {
      for (final inset in const [.029, .039]) {
        canvas.drawRRect(
          ui.RRect.fromRectAndRadius(
            ui.Rect.fromLTWH(
              size.width * inset,
              size.height * inset,
              size.width * (1 - inset * 2),
              size.height * (1 - inset * 2),
            ),
            ui.Radius.circular(size.width * .054),
          ),
          paint,
        );
      }
      for (var index = 0; index < 4; index++) {
        canvas.save();
        canvas.translate(size.width / 2, size.height / 2);
        canvas.rotate(index * math.pi / 2);
        canvas.translate(-size.width / 2, -size.height / 2);
        _star(
          canvas,
          ui.Offset(size.width / 2, size.width * .034),
          size.width * .007,
          paint,
        );
        canvas.restore();
      }
    }
  }

  Future<SkinArtwork> _paintNocturne(SkinPalette palette) async {
    final result = <SkinSurface, ui.Image>{};
    ui.Image? metallicRoughness;
    try {
      final ({ui.Image metal, ui.Image surface}) board = await _nocturneBoard(
        palette,
      );
      result[SkinSurface.board] = board.surface;
      metallicRoughness = board.metal;
      result[SkinSurface.darkCap] = await _nocturneCap(palette, true);
      result[SkinSurface.darkBody] = await _nocturneBody(palette, true);
      result[SkinSurface.lightCap] = await _nocturneCap(palette, false);
      result[SkinSurface.lightBody] = await _nocturneBody(palette, false);
      return SkinArtwork(
        Map.unmodifiable(result),
        metallicRoughness: metallicRoughness,
      );
    } on Object {
      for (final ui.Image image in result.values) {
        image.dispose();
      }
      metallicRoughness?.dispose();
      rethrow;
    }
  }

  Future<ui.Image> _picture(
    int width,
    int height,
    void Function(ui.Canvas canvas) draw,
  ) {
    final recorder = ui.PictureRecorder();
    draw(ui.Canvas(recorder));
    return recorder.endRecording().toImage(width, height);
  }

  void _nocturneStar(
    ui.Canvas canvas,
    ui.Offset center,
    double size,
    ui.Paint paint,
  ) {
    final path = ui.Path()
      ..moveTo(center.dx, center.dy - size)
      ..quadraticBezierTo(
        center.dx + size * .18,
        center.dy - size * .18,
        center.dx + size,
        center.dy,
      )
      ..quadraticBezierTo(
        center.dx + size * .18,
        center.dy + size * .18,
        center.dx,
        center.dy + size,
      )
      ..quadraticBezierTo(
        center.dx - size * .18,
        center.dy + size * .18,
        center.dx - size,
        center.dy,
      )
      ..quadraticBezierTo(
        center.dx - size * .18,
        center.dy - size * .18,
        center.dx,
        center.dy - size,
      )
      ..close();
    canvas.drawPath(path, paint..style = ui.PaintingStyle.fill);
  }

  void _nocturneRosette(
    ui.Canvas canvas,
    ui.Offset center,
    double radius,
    int petals,
    ui.Paint paint,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    for (var index = 0; index < petals; index++) {
      canvas.rotate(math.pi * 2 / petals);
      final path = ui.Path()
        ..moveTo(0, 0)
        ..cubicTo(
          -radius * .36,
          -radius * .48,
          -radius * .24,
          -radius * .82,
          0,
          -radius,
        )
        ..cubicTo(
          radius * .24,
          -radius * .82,
          radius * .36,
          -radius * .48,
          0,
          0,
        );
      canvas.drawPath(path, paint..style = ui.PaintingStyle.stroke);
    }
    _circle(canvas, ui.Offset.zero, radius * .19, paint);
    canvas.restore();
  }

  void _nocturneBranch(
    ui.Canvas canvas,
    ui.Offset origin,
    double angle,
    double length,
    ui.Paint paint,
  ) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.rotate(angle);
    final stem = ui.Path()
      ..moveTo(0, 0)
      ..cubicTo(
        length * .2,
        -length * .14,
        length * .7,
        length * .14,
        length,
        0,
      );
    canvas.drawPath(stem, paint..style = ui.PaintingStyle.stroke);
    for (var index = 1; index < 10; index++) {
      final double x = length * index / 11;
      final double bend = math.sin(index / 11 * math.pi * 2) * length * -.025;
      for (final side in const [-1, 1]) {
        final leaf = ui.Path()
          ..moveTo(x - 5, bend)
          ..cubicTo(
            x + 5,
            bend + side * 17,
            x + 15,
            bend + side * 23,
            x + 22,
            bend + side * 23,
          )
          ..cubicTo(
            x + 23,
            bend + side * 10,
            x + 10,
            bend + side * 6,
            x - 5,
            bend,
          );
        canvas.drawPath(leaf, paint..style = ui.PaintingStyle.stroke);
        canvas.drawLine(
          ui.Offset(x, bend),
          ui.Offset(x + 18, bend + side * 19),
          paint,
        );
      }
    }
    canvas.restore();
  }

  void _nocturneGrain(ui.Canvas canvas, int width, int height) {
    var seed = 804;
    double random() {
      seed = (seed * 1664525 + 1013904223) & 0xffffffff;
      return seed / 4294967296;
    }

    final light = ui.Paint()..color = const ui.Color(0x06FFFFFF);
    final dark = ui.Paint()..color = const ui.Color(0x05000000);
    for (var index = 0; index < 6500; index++) {
      canvas.drawRect(
        ui.Rect.fromLTWH(random() * width, random() * height, 1, 1),
        index.isOdd ? light : dark,
      );
    }
  }

  Future<({ui.Image metal, ui.Image surface})> _nocturneBoard(
    SkinPalette palette,
  ) async {
    final ui.Image surface = await _picture(1024, 1024, (canvas) {
      canvas.drawColor(color(palette.board.body), ui.BlendMode.src);
      canvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, 1024, 1024),
        ui.Paint()
          ..shader = ui.Gradient.linear(
            ui.Offset.zero,
            const ui.Offset(1024, 1024),
            const [
              ui.Color(0x0EFFFFFF),
              ui.Color(0x00FFFFFF),
              ui.Color(0x29000000),
            ],
            const [0, .5, 1],
          ),
      );
      _nocturneGrain(canvas, 1024, 1024);
      final ui.Paint accent = ui.Paint()
        ..color = color(palette.accent)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1.8;
      for (final inset in const [28.0, 38.0]) {
        canvas.drawRRect(
          ui.RRect.fromRectAndRadius(
            ui.Rect.fromLTWH(inset, inset, 1024 - inset * 2, 1024 - inset * 2),
            const ui.Radius.circular(55),
          ),
          accent,
        );
      }
      for (var corner = 0; corner < 4; corner++) {
        canvas.save();
        canvas.translate(512, 512);
        canvas.rotate(corner * math.pi / 2);
        canvas.translate(-512, -512);
        _nocturneRosette(canvas, const ui.Offset(76, 76), 38, 8, accent);
        _nocturneBranch(canvas, const ui.Offset(102, 67), 0, 243, accent);
        _nocturneBranch(
          canvas,
          const ui.Offset(67, 102),
          math.pi / 2,
          243,
          accent,
        );
        _nocturneStar(canvas, const ui.Offset(512, 33), 8, accent);
        canvas.restore();
      }
      final ui.Paint astronomy = ui.Paint()
        ..color = color(palette.accent).withValues(alpha: .57)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1.8;
      const ui.Offset center = ui.Offset(512, 512);
      for (final radius in const [181.0, 304.0, 422.0]) {
        _circle(canvas, center, radius, astronomy);
      }
      for (final angle in const [-.58, .65]) {
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(angle);
        canvas.drawOval(
          ui.Rect.fromCenter(center: ui.Offset.zero, width: 888, height: 308),
          astronomy,
        );
        canvas.restore();
      }
      for (var index = 0; index < 72; index++) {
        final double angle = index * math.pi / 36;
        canvas.drawLine(
          center + ui.Offset(math.cos(angle) * 414, math.sin(angle) * 414),
          center +
              ui.Offset(
                math.cos(angle) * (index % 6 == 0 ? 398 : 409),
                math.sin(angle) * (index % 6 == 0 ? 398 : 409),
              ),
          astronomy,
        );
      }
      for (var y = 0; y < 5; y++) {
        for (var x = 0; x < 5; x++) {
          final point = ui.Offset(
            512 + ((x - 2) * 1.09 / 6.09) * 1024,
            512 + ((y - 2) * 1.09 / 6.09) * 1024,
          );
          canvas.drawCircle(
            point,
            62,
            ui.Paint()
              ..color = color(palette.board.body).withValues(alpha: .38),
          );
          final ui.Paint seal = ui.Paint()
            ..color = color(palette.accent).withValues(alpha: .63)
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = 1.8;
          _circle(canvas, point, 55, seal);
          _circle(canvas, point, 51, seal);
          final ui.Paint rosette = ui.Paint()
            ..color = color(palette.accent).withValues(alpha: .78)
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = 1.8;
          _nocturneRosette(canvas, point, 31, (x + y).isOdd ? 8 : 12, rosette);
          for (var index = 0; index < 8; index++) {
            final double angle = index * math.pi / 4;
            _nocturneStar(
              canvas,
              point + ui.Offset(math.cos(angle) * 44, math.sin(angle) * 44),
              index.isOdd ? 2 : 3.3,
              rosette,
            );
          }
        }
      }
      final ui.Paint constellation = ui.Paint()
        ..color = color(palette.accent).withValues(alpha: .7)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1.8;
      const points = <ui.Offset>[
        ui.Offset(230, 112),
        ui.Offset(386, 254),
        ui.Offset(578, 203),
        ui.Offset(799, 356),
        ui.Offset(857, 580),
        ui.Offset(672, 786),
        ui.Offset(362, 837),
        ui.Offset(159, 654),
      ];
      final path = ui.Path()..moveTo(points.first.dx, points.first.dy);
      for (final ui.Offset point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, constellation);
      for (final point in points) {
        _nocturneStar(canvas, point, 7, constellation);
      }
    });
    return (surface: surface, metal: await _metallicRoughnessFrom(surface));
  }

  Future<ui.Image> _nocturneCap(SkinPalette palette, bool dark) {
    final PiecePalette colors = dark ? palette.dark : palette.light;
    return _picture(512, 512, (canvas) {
      canvas.drawColor(color(colors.cap), ui.BlendMode.src);
      _nocturneGrain(canvas, 512, 512);
      final ui.Paint ink = ui.Paint()
        ..color = color(dark ? palette.accent : colors.mark)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 2.5;
      const center = ui.Offset(256, 256);
      _circle(canvas, center, 219, ink);
      _circle(canvas, center, 204, ink);
      ink.strokeWidth = 1.6;
      for (var index = 0; index < 40; index++) {
        final double angle = index * math.pi / 20;
        _nocturneStar(
          canvas,
          center + ui.Offset(math.cos(angle) * 211, math.sin(angle) * 211),
          index % 5 == 0 ? 4 : 2,
          ink,
        );
      }
      if (dark) {
        final moon = ui.Path()
          ..moveTo(296, 164)
          ..cubicTo(166, 124, 133, 331, 259, 352)
          ..cubicTo(207, 302, 207, 206, 296, 164)
          ..close();
        canvas.drawPath(moon, ink..style = ui.PaintingStyle.fill);
        _circle(
          canvas,
          center,
          142,
          ui.Paint()
            ..color = ink.color.withValues(alpha: .55)
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
        ink
          ..style = ui.PaintingStyle.stroke
          ..color = color(palette.accent);
        const stars = <(double, double, double)>[
          (320, 251, 22),
          (286, 306, 9),
          (304, 208, 8),
          (346, 307, 5),
        ];
        for (final star in stars) {
          _nocturneStar(canvas, ui.Offset(star.$1, star.$2), star.$3, ink);
        }
        canvas.drawPath(
          ui.Path()
            ..moveTo(283, 300)
            ..lineTo(320, 251)
            ..lineTo(304, 208),
          ink..style = ui.PaintingStyle.stroke,
        );
      } else {
        ink.strokeWidth = 4.8;
        _nocturneRosette(canvas, center, 129, 12, ink);
        _circle(canvas, center, 58, ink);
        _circle(canvas, center, 49, ink);
        ink.strokeWidth = 3;
        for (var index = 0; index < 24; index++) {
          final double angle = index * math.pi / 12;
          canvas.drawLine(
            center + ui.Offset(math.cos(angle) * 140, math.sin(angle) * 140),
            center +
                ui.Offset(
                  math.cos(angle) * (index.isOdd ? 153 : 173),
                  math.sin(angle) * (index.isOdd ? 153 : 173),
                ),
            ink,
          );
        }
        _nocturneStar(canvas, center, 30, ink);
      }
    });
  }

  Future<ui.Image> _nocturneBody(SkinPalette palette, bool dark) {
    final PiecePalette colors = dark ? palette.dark : palette.light;
    return _picture(512, 256, (canvas) {
      canvas.drawColor(color(colors.body), ui.BlendMode.src);
      _nocturneGrain(canvas, 512, 256);
      final ui.Paint ink = ui.Paint()
        ..color = color(dark ? palette.accent : palette.light.mark)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 2;
      for (final y in const [32.0, 40.0, 215.0, 223.0]) {
        canvas.drawLine(ui.Offset(0, y), ui.Offset(512, y), ink);
      }
      ink.strokeWidth = 1.25;
      for (var index = -1; index < 9; index++) {
        final ui.Offset center = ui.Offset(index * 64 + 32, 128);
        _nocturneRosette(canvas, center, 29, 6, ink);
        final top = ui.Path()
          ..moveTo(center.dx - 32, center.dy)
          ..quadraticBezierTo(
            center.dx - 18,
            center.dy - 45,
            center.dx,
            center.dy - 40,
          )
          ..quadraticBezierTo(
            center.dx + 18,
            center.dy - 45,
            center.dx + 32,
            center.dy,
          );
        final bottom = ui.Path()
          ..moveTo(center.dx - 32, center.dy)
          ..quadraticBezierTo(
            center.dx - 18,
            center.dy + 45,
            center.dx,
            center.dy + 40,
          )
          ..quadraticBezierTo(
            center.dx + 18,
            center.dy + 45,
            center.dx + 32,
            center.dy,
          );
        canvas
          ..drawPath(top, ink)
          ..drawPath(bottom, ink);
      }
    });
  }

  Future<ui.Image> _metallicRoughnessFrom(ui.Image surface) async {
    final ByteData? data = await surface.toByteData();
    if (data == null) throw StateError('Unable to read Nocturne board pixels');
    final Uint8List source = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final Uint8List bytes = Uint8List(source.length);
    for (var index = 0; index < source.length; index += 4) {
      final int mask = ((source[index] - 35) * 1.7).round().clamp(24, 255);
      bytes[index] = 255;
      bytes[index + 1] = 255;
      bytes[index + 2] = mask;
      bytes[index + 3] = 255;
    }
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
      bytes,
    );
    final ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: surface.width,
      height: surface.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    try {
      final ui.Codec codec = await descriptor.instantiateCodec();
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
      buffer.dispose();
    }
  }

  List<({double x, double y, double rotation})> layerPositions(
    DesignLayer layer,
    double width,
    double height,
  ) {
    final double size = math.min(width, height) * layer.size;
    if (layer.placement == LayerPlacement.single) {
      return [
        (x: layer.x * width, y: layer.y * height, rotation: layer.rotation),
      ];
    }
    if (layer.placement == LayerPlacement.corners) {
      final double x = size / 2 + width * (.035 + (layer.x - .5) * .25);
      final double y = size / 2 + height * (.035 + (layer.y - .5) * .25);
      return [
        (x: x, y: y, rotation: layer.rotation),
        (x: width - x, y: y, rotation: layer.rotation + 90),
        (x: width - x, y: height - y, rotation: layer.rotation + 180),
        (x: x, y: height - y, rotation: layer.rotation + 270),
      ];
    }
    final double step = math.max(size * 1.4, math.min(width, height) * .14);
    final int columns = math.min(12, (width / step).ceil());
    final int rows = math.min(8, (height / step).ceil());
    return [
      for (var index = 0; index < columns * rows; index++)
        (
          x: ((index % columns) + layer.x) * width / columns,
          y: ((index ~/ columns) + layer.y) * height / rows,
          rotation: layer.rotation,
        ),
    ];
  }

  void _layers(ui.Canvas canvas, ui.Size canvasSize, List<DesignLayer> layers) {
    for (final layer in layers) {
      final ui.Image? image = layer is ImageDesignLayer
          ? imageCache.loaded(layer.imageId)
          : null;
      if (layer is ImageDesignLayer && image == null) continue;
      final double extent =
          math.min(canvasSize.width, canvasSize.height) * layer.size;
      for (final ({double rotation, double x, double y}) point
          in layerPositions(layer, canvasSize.width, canvasSize.height)) {
        canvas.save();
        canvas.translate(point.x, point.y);
        canvas.rotate(point.rotation * math.pi / 180);
        if (layer is MotifDesignLayer) {
          _motif(
            canvas,
            layer.motif,
            extent,
            ui.Paint()
              ..color = color(layer.color).withValues(alpha: layer.opacity),
          );
        } else if (image != null) {
          final double ratio = image.width / image.height;
          final double width = ratio >= 1 ? extent : extent * ratio;
          final double height = ratio >= 1 ? extent / ratio : extent;
          final destination = ui.Rect.fromCenter(
            center: ui.Offset.zero,
            width: width,
            height: height,
          );
          final paint = ui.Paint()
            ..color = ui.Color.fromRGBO(255, 255, 255, layer.opacity);
          if (layer.tint) {
            paint.colorFilter = ui.ColorFilter.mode(
              color(layer.color),
              ui.BlendMode.srcIn,
            );
          }
          canvas.drawImageRect(
            image,
            ui.Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            ),
            destination,
            paint,
          );
        }
        canvas.restore();
      }
    }
  }
}

ui.Color color(String hex) =>
    ui.Color(int.parse('ff${hex.substring(1)}', radix: 16));

SkinDesign nocturneDesign() {
  SurfaceDesign base({
    SkinPattern pattern = SkinPattern.none,
    String ink = '#d8bc7f',
    double opacity = .65,
    bool border = false,
    double roughness = .5,
    double metalness = 0,
    List<DesignLayer> layers = const [],
  }) => SurfaceDesign(
    pattern: pattern,
    ink: ink,
    patternScale: 1,
    patternOpacity: opacity,
    border: border,
    roughness: roughness,
    metalness: metalness,
    layers: layers,
  );
  MotifDesignLayer motif(
    String id,
    SkinMotif motif, {
    String color = '#d8bc7f',
    double size = .56,
    LayerPlacement placement = LayerPlacement.single,
  }) => MotifDesignLayer(
    id: id,
    motif: motif,
    x: .5,
    y: .5,
    size: size,
    rotation: 0,
    opacity: 1,
    color: color,
    tint: false,
    placement: placement,
  );
  return SkinDesign(
    surfaces: {
      SkinSurface.board: base(
        pattern: SkinPattern.celestial,
        opacity: .8,
        border: true,
        roughness: .3,
        metalness: .55,
        layers: [
          motif(
            'laurel',
            SkinMotif.laurel,
            size: .2,
            placement: LayerPlacement.corners,
          ),
        ],
      ),
      SkinSurface.darkCap: base(
        pattern: SkinPattern.celestial,
        opacity: .5,
        border: true,
        roughness: .36,
        metalness: .2,
        layers: [motif('moon', SkinMotif.moon, color: '#dfc688')],
      ),
      SkinSurface.lightCap: base(
        pattern: SkinPattern.guilloche,
        ink: '#947244',
        opacity: .3,
        border: true,
        roughness: .42,
        metalness: .1,
        layers: [motif('sun', SkinMotif.sun, color: '#947244')],
      ),
      SkinSurface.darkBody: base(
        pattern: SkinPattern.botanical,
        opacity: .5,
        border: true,
        roughness: .38,
        metalness: .15,
      ),
      SkinSurface.lightBody: base(
        pattern: SkinPattern.botanical,
        ink: '#947244',
        opacity: .4,
        border: true,
        roughness: .44,
        metalness: .08,
      ),
    },
  );
}
