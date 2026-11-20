import 'dart:math' as math;

double _r(double v, int digits) => double.parse(v.toStringAsFixed(digits));

/// 单个触摸采样点。t 为相对本次采集开始的毫秒数，rawUs 为系统事件时间戳。
class TouchPoint {
  final double t;
  final int rawUs;
  final double x;
  final double y;
  final double pressure;
  final double pressureMin;
  final double pressureMax;
  final double tilt;

  const TouchPoint({
    required this.t,
    required this.rawUs,
    required this.x,
    required this.y,
    required this.pressure,
    required this.pressureMin,
    required this.pressureMax,
    required this.tilt,
  });

  Map<String, dynamic> toJson() => {
        't': _r(t, 3),
        'raw_us': rawUs,
        'x': _r(x, 2),
        'y': _r(y, 2),
        'p': _r(pressure, 4),
        'p_min': _r(pressureMin, 4),
        'p_max': _r(pressureMax, 4),
        'tilt': _r(tilt, 3),
      };
}

/// 一笔：从按下到抬起。
class Stroke {
  int index;
  double startT;
  double endT;
  bool cancelled;
  String kind;
  final List<TouchPoint> points;

  Stroke({
    required this.index,
    required this.startT,
    required this.endT,
    required this.points,
    this.cancelled = false,
    this.kind = 'unknown',
  });

  double get durationMs => endT - startT;

  Map<String, dynamic> toJson() => {
        'index': index,
        'kind': kind,
        'start_t': _r(startT, 3),
        'end_t': _r(endT, 3),
        'duration_ms': _r(durationMs, 3),
        'cancelled': cancelled,
        'point_count': points.length,
        'points': points.map((p) => p.toJson()).toList(),
      };
}

/// 采集统计，用于现场判断数据质量（尤其是压力是否真实）。
class SampleStats {
  final int strokeCount;
  final int pointCount;
  final double durationMs;
  final double sampleRateHz;
  final double pressureMin;
  final double pressureMax;
  final double pressureMean;
  final double pressureStd;
  final int pressureDistinct;
  final double speedMeanPxPerMs;
  final double speedMaxPxPerMs;
  final List<double> interStrokeGapsMs;

  const SampleStats({
    required this.strokeCount,
    required this.pointCount,
    required this.durationMs,
    required this.sampleRateHz,
    required this.pressureMin,
    required this.pressureMax,
    required this.pressureMean,
    required this.pressureStd,
    required this.pressureDistinct,
    required this.speedMeanPxPerMs,
    required this.speedMaxPxPerMs,
    required this.interStrokeGapsMs,
  });

  Map<String, dynamic> toJson() => {
        'stroke_count': strokeCount,
        'point_count': pointCount,
        'duration_ms': _r(durationMs, 3),
        'sample_rate_hz': _r(sampleRateHz, 2),
        'pressure_min': _r(pressureMin, 4),
        'pressure_max': _r(pressureMax, 4),
        'pressure_mean': _r(pressureMean, 4),
        'pressure_std': _r(pressureStd, 4),
        'pressure_distinct': pressureDistinct,
        'speed_mean_px_per_ms': _r(speedMeanPxPerMs, 4),
        'speed_max_px_per_ms': _r(speedMaxPxPerMs, 4),
        'inter_stroke_gaps_ms':
            interStrokeGapsMs.map((g) => _r(g, 3)).toList(),
      };
}

/// 一次采集样本。
class CaptureSample {
  final String schema = 'gesture-sample-v1';
  final String subjectId;
  final String gestureId;
  final String condition;
  final int sampleIndex;
  final String sessionId;
  final String capturedAt;
  final Map<String, dynamic> device;
  final Map<String, dynamic> canvas;
  final String inputMode;
  final bool multiTouchDetected;
  final List<Stroke> strokes;
  final SampleStats stats;
  final String notes;

  CaptureSample({
    required this.subjectId,
    required this.gestureId,
    required this.condition,
    required this.sampleIndex,
    required this.sessionId,
    required this.capturedAt,
    required this.device,
    required this.canvas,
    required this.inputMode,
    required this.multiTouchDetected,
    required this.strokes,
    required this.stats,
    this.notes = '',
  });

  Map<String, dynamic> toJson() => {
        'schema': schema,
        'subject_id': subjectId,
        'gesture_id': gestureId,
        'condition': condition,
        'sample_index': sampleIndex,
        'session_id': sessionId,
        'captured_at': capturedAt,
        'device': device,
        'canvas': canvas,
        'input_mode': inputMode,
        'multi_touch_detected': multiTouchDetected,
        'stroke_count': strokes.length,
        'strokes': strokes.map((s) => s.toJson()).toList(),
        'stats': stats.toJson(),
        'notes': notes,
      };
}

/// 计算统计量，输入为按时间排序的原始点。
SampleStats computeStats(List<Stroke> strokes, {bool multiTouch = false}) {
  final pressures = <double>[];
  final speeds = <double>[];
  final allT = <double>[];

  for (final s in strokes) {
    for (var i = 0; i < s.points.length; i++) {
      final p = s.points[i];
      pressures.add(p.pressure);
      allT.add(p.t);
      if (i > 0) {
        final q = s.points[i - 1];
        final dt = p.t - q.t;
        if (dt > 0) {
          final dx = p.x - q.x;
          final dy = p.y - q.y;
          speeds.add(math.sqrt(dx * dx + dy * dy) / dt);
        }
      }
    }
  }

  double mean(List<double> v) =>
      v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
  double std(List<double> v) {
    if (v.length < 2) return 0;
    final m = mean(v);
    final s = v.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b);
    return math.sqrt(s / (v.length - 1));
  }

  final gaps = <double>[];
  for (var i = 1; i < strokes.length; i++) {
    gaps.add(strokes[i].startT - strokes[i - 1].endT);
  }

  final sortedT = [...allT]..sort();
  final duration = sortedT.isEmpty ? 0.0 : sortedT.last - sortedT.first;
  final rate = duration > 0 ? (allT.length - 1) / duration * 1000 : 0.0;

  return SampleStats(
    strokeCount: strokes.length,
    pointCount: allT.length,
    durationMs: duration,
    sampleRateHz: rate,
    pressureMin: pressures.isEmpty ? 0 : pressures.reduce(math.min),
    pressureMax: pressures.isEmpty ? 0 : pressures.reduce(math.max),
    pressureMean: mean(pressures),
    pressureStd: std(pressures),
    pressureDistinct:
        pressures.map((p) => p.toStringAsFixed(4)).toSet().length,
    speedMeanPxPerMs: mean(speeds),
    speedMaxPxPerMs: speeds.isEmpty ? 0 : speeds.reduce(math.max),
    interStrokeGapsMs: gaps,
  );
}
