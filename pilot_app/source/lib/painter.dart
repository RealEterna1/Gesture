import 'package:flutter/material.dart';

import 'models.dart';

/// 画布：绘制已完成笔画与当前笔画。
class GesturePainter extends CustomPainter {
  final List<Stroke> strokes;
  final List<TouchPoint> current;
  final Listenable revision;
  final Color color;

  GesturePainter({
    required this.strokes,
    required this.current,
    required this.revision,
    required this.color,
  }) : super(repaint: revision);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final s in strokes) {
      _drawStroke(canvas, s.points, paint);
    }
    _drawStroke(canvas, current, paint);

    // 起点标记，便于观察不同试次起笔位置差异
    if (strokes.isNotEmpty && strokes.first.points.isNotEmpty) {
      final p = strokes.first.points.first;
      canvas.drawCircle(
        Offset(p.x, p.y),
        5,
        Paint()..color = color.withValues(alpha: 0.35),
      );
    }
  }

  void _drawStroke(Canvas canvas, List<TouchPoint> pts, Paint paint) {
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      canvas.drawCircle(Offset(pts.first.x, pts.first.y), 2, paint);
      return;
    }
    final path = Path()..moveTo(pts.first.x, pts.first.y);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].x, pts[i].y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant GesturePainter old) => true;
}
