import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';

/// 实时压力/速度曲线，用于现场判断压力是否为真实变化。
class LiveCurve extends StatelessWidget {
  final List<Stroke> strokes;
  final List<TouchPoint> current;
  final Listenable revision;

  const LiveCurve({
    super.key,
    required this.strokes,
    required this.current,
    required this.revision,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: revision,
      builder: (context, _) {
        final points = <TouchPoint>[];
        for (final s in strokes) {
          points.addAll(s.points);
        }
        points.addAll(current);
        return SizedBox(
          height: 46,
          width: double.infinity,
          child: CustomPaint(
            painter: _CurvePainter(
              points: points,
              color: Theme.of(context).colorScheme.primary,
              gridColor: Colors.white12,
            ),
          ),
        );
      },
    );
  }
}

class _CurvePainter extends CustomPainter {
  final List<TouchPoint> points;
  final Color color;
  final Color gridColor;

  _CurvePainter({
    required this.points,
    required this.color,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      grid,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.5),
      Offset(size.width, size.height * 0.5),
      grid,
    );

    if (points.length < 2) return;

    final maxPressure = math.max(
      1.0,
      points.map((p) => p.pressureMax).fold<double>(0, math.max),
    );
    final n = points.length;
    final path = Path();
    for (var i = 0; i < n; i++) {
      final x = size.width * i / (n - 1);
      final v = (points[i].pressure / maxPressure).clamp(0.0, 1.0);
      final y = size.height - 2 - v * (size.height - 6);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );

    // 当前点
    final last = points.last;
    final v = (last.pressure / maxPressure).clamp(0.0, 1.0);
    canvas.drawCircle(
      Offset(size.width - 2, size.height - 2 - v * (size.height - 6)),
      3,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) =>
      old.points.length != points.length || old.color != color;
}
