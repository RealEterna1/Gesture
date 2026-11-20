import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_collector/models.dart';

TouchPoint _p(double t, double x, double y, double pressure) => TouchPoint(
      t: t,
      rawUs: (t * 1000).round(),
      x: x,
      y: y,
      pressure: pressure,
      pressureMin: 0,
      pressureMax: 1,
      tilt: 0,
    );

void main() {
  test('computeStats 汇总笔画、点数与压力统计', () {
    final strokes = [
      Stroke(
        index: 0,
        startT: 0,
        endT: 20,
        points: [_p(0, 0, 0, 0.4), _p(10, 10, 0, 0.6), _p(20, 20, 0, 0.5)],
      ),
      Stroke(
        index: 1,
        startT: 40,
        endT: 60,
        points: [_p(40, 20, 20, 0.5), _p(60, 40, 20, 0.5)],
      ),
    ];

    final s = computeStats(strokes);

    expect(s.strokeCount, 2);
    expect(s.pointCount, 5);
    expect(s.pressureMin, closeTo(0.4, 1e-9));
    expect(s.pressureMax, closeTo(0.6, 1e-9));
    expect(s.pressureDistinct, 3);
    expect(s.interStrokeGapsMs, [20]);
    expect(s.durationMs, 60);
  });
}
