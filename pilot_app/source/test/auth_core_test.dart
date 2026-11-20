import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_collector/auth/auth_core.dart';
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

Stroke _stroke(int index, List<TouchPoint> points) => Stroke(
      index: index,
      startT: points.first.t,
      endT: points.last.t,
      points: points,
      kind: 'stylus',
    );

List<TouchPoint> _line(
  double x0,
  double y0,
  double x1,
  double y1, {
  double pressure = 0.4,
  double stepMs = 16,
}) {
  final points = <TouchPoint>[];
  var t = 0.0;
  for (var k = 0; k <= 8; k++) {
    final f = k / 8.0;
    points.add(
      _p(
        t,
        x0 + (x1 - x0) * f,
        y0 + (y1 - y0) * f,
        pressure + 0.01 * (k % 3),
      ),
    );
    t += stepMs;
  }
  return points;
}

CaptureSample _sample(
  int index, {
  double pressure = 0.4,
  bool twoStrokes = false,
}) {
  final strokes = <Stroke>[
    _stroke(0, _line(100, 100, 400, 100, pressure: pressure)),
    _stroke(1, _line(400, 100, 250, 350, pressure: pressure)),
    if (!twoStrokes)
      _stroke(2, _line(250, 350, 100, 100, pressure: pressure)),
  ];
  final stats = computeStats(strokes);
  return CaptureSample(
    subjectId: 'P01',
    gestureId: 'G1',
    condition: 'genuine',
    sampleIndex: index,
    sessionId: 'test',
    capturedAt: '',
    device: const {},
    canvas: const {},
    inputMode: 'stylus',
    multiTouchDetected: false,
    strokes: strokes,
    stats: stats,
  );
}

void main() {
  test('shape helpers and features', () {
    final sample = _sample(0);
    final a = ShapeUtil.normalize(
      ShapeUtil.resample(sample.strokes.first.points),
    );
    expect(ShapeUtil.dtw(a, a), closeTo(0, 1e-9));
    expect(AuthFeatures.stroke(sample.strokes.first).length, 14);
    expect(AuthFeatures.inter(sample).length, 7);
  });

  test('template builds, verifies and rejects wrong stroke count', () {
    final samples = List<CaptureSample>.generate(
      6,
      (i) => _sample(i, pressure: 0.35 + i * 0.01),
    );
    final template = AuthTemplate.build(
      subjectId: 'P01',
      gestureId: 'G1',
      samples: samples,
    );

    expect(template.strokeCount, 3);
    expect(template.shapeTemplate.length, 3);
    expect(template.shapeThreshold, greaterThan(0));
    expect(template.behaviorThreshold, greaterThan(0));

    final accepted = template.verify(samples.first);
    expect(accepted.accepted, isTrue, reason: accepted.reason);

    final rejected = template.verify(_sample(99, twoStrokes: true));
    expect(rejected.accepted, isFalse);

    final restored = AuthTemplate.fromJson(template.toJson());
    expect(restored.strokeCount, 3);
    expect(restored.subjectId, 'P01');
  });
}
