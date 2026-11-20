import 'dart:math' as math;

import '../models.dart';

/// 端上认证核心：形状层（重采样 + DTW）、行为层（逐笔特征 + 距离）、模板与判定。
/// 与离线 analysis/auth_eval.py 的特征顺序保持一致。

const int kResamplePoints = 64;

class AuthFeatures {
  static const int dimension = 14;

  /// 每笔特征，顺序必须与离线脚本一致：
  /// duration, path, speed_mean, speed_median, speed_p90,
  /// acc_mean_abs, acc_std, pressure_mean, pressure_std,
  /// pressure_min, pressure_max, pressure_slope,
  /// pressure_speed_corr, straightness
  static List<double> stroke(Stroke stroke) {
    final pts = stroke.points;
    if (pts.isEmpty) return List<double>.filled(dimension, 0.0);

    final n = pts.length;
    final t = List<double>.generate(n, (i) => pts[i].t / 1000.0);
    final pressure = List<double>.generate(n, (i) => pts[i].pressure);

    final dt = <double>[];
    final step = <double>[];
    for (var i = 1; i < n; i++) {
      dt.add(t[i] - t[i - 1]);
      final dx = pts[i].x - pts[i - 1].x;
      final dy = pts[i].y - pts[i - 1].y;
      step.add(math.sqrt(dx * dx + dy * dy));
    }

    final speeds = <double>[];
    for (var i = 0; i < dt.length; i++) {
      if (dt[i] > 1e-9) speeds.add(step[i] / dt[i]);
    }
    if (speeds.isEmpty) speeds.add(0.0);

    final duration = math.max(t.last - t.first, 1e-6);
    final path = step.fold<double>(0.0, (a, b) => a + b);
    final chord = n > 1
        ? math.sqrt(
            math.pow(pts.last.x - pts.first.x, 2) +
                math.pow(pts.last.y - pts.first.y, 2),
          )
        : 0.0;
    final straightness = path > 1e-9 ? chord / path : 0.0;

    final acc = <double>[];
    for (var i = 1; i < speeds.length; i++) {
      final d = i < dt.length ? dt[i] : 1e-6;
      if (d > 1e-9) acc.add((speeds[i] - speeds[i - 1]) / d);
    }

    final pressureSlope = _slope(
      List<double>.generate(n, (i) => t[i] - t.first),
      pressure,
    );

    final m = math.min(speeds.length, pressure.length - 1);
    final corr = m > 2
        ? _corr(pressure.sublist(1, 1 + m), speeds.sublist(0, m))
        : 0.0;

    final sortedSpeeds = [...speeds]..sort();

    return <double>[
      duration,
      path,
      _mean(speeds),
      _median(sortedSpeeds),
      _percentile(sortedSpeeds, 0.90),
      _mean(acc.map((v) => v.abs()).toList()),
      _std(acc),
      _mean(pressure),
      _std(pressure),
      _min(pressure),
      _max(pressure),
      pressureSlope,
      corr,
      straightness,
    ];
  }

  /// 笔间特征：总时长、停顿统计、各笔相对时长。
  static List<double> inter(CaptureSample sample) {
    final strokes = sample.strokes;
    if (strokes.isEmpty) return <double>[0, 0, 0, 0];

    final durations = strokes
        .map((s) => math.max(s.durationMs / 1000.0, 1e-6))
        .toList();
    final total = durations.fold<double>(0.0, (a, b) => a + b);
    final relative = total > 1e-9
        ? durations.map((d) => d / total).toList()
        : List<double>.filled(durations.length, 0.0);

    final pauses = <double>[];
    for (var i = 1; i < strokes.length; i++) {
      final gap = (strokes[i].startT - strokes[i - 1].endT) / 1000.0;
      pauses.add(math.max(gap, 0.0));
    }
    if (pauses.isEmpty) pauses.add(0.0);

    return <double>[
      total,
      _mean(pauses),
      _max(pauses),
      pauses.fold<double>(0.0, (a, b) => a + b),
      ...relative,
    ];
  }
}

class ShapeUtil {
  static List<List<double>> resample(
    List<TouchPoint> points, [
    int n = kResamplePoints,
  ]) {
    if (points.isEmpty) {
      return List<List<double>>.generate(n, (_) => <double>[0, 0]);
    }
    if (points.length == 1) {
      return List<List<double>>.generate(
        n,
        (_) => <double>[points.first.x, points.first.y],
      );
    }

    final cum = <double>[0.0];
    for (var i = 1; i < points.length; i++) {
      final dx = points[i].x - points[i - 1].x;
      final dy = points[i].y - points[i - 1].y;
      cum.add(cum.last + math.sqrt(dx * dx + dy * dy));
    }
    final total = cum.last;
    if (total < 1e-9) {
      return List<List<double>>.generate(
        n,
        (_) => <double>[points.first.x, points.first.y],
      );
    }

    final out = <List<double>>[];
    var seg = 1;
    for (var k = 0; k < n; k++) {
      final target = total * k / (n - 1);
      while (seg < cum.length - 1 && cum[seg] < target) {
        seg++;
      }
      final t0 = cum[seg - 1];
      final t1 = cum[seg];
      final f = (t1 - t0) > 1e-9 ? (target - t0) / (t1 - t0) : 0.0;
      out.add(<double>[
        points[seg - 1].x + (points[seg].x - points[seg - 1].x) * f,
        points[seg - 1].y + (points[seg].y - points[seg - 1].y) * f,
      ]);
    }
    return out;
  }

  static List<List<double>> normalize(List<List<double>> points) {
    if (points.isEmpty) return points;
    final mx = _mean(points.map((p) => p[0]).toList());
    final my = _mean(points.map((p) => p[1]).toList());
    var rms = 0.0;
    for (final p in points) {
      final dx = p[0] - mx;
      final dy = p[1] - my;
      rms += dx * dx + dy * dy;
    }
    rms = math.sqrt(rms / points.length);
    if (rms < 1e-9) {
      return points.map((p) => <double>[p[0] - mx, p[1] - my]).toList();
    }
    return points
        .map((p) => <double>[(p[0] - mx) / rms, (p[1] - my) / rms])
        .toList();
  }

  static double dtw(List<List<double>> a, List<List<double>> b) {
    final n = a.length;
    final m = b.length;
    if (n == 0 || m == 0) return double.infinity;

    final acc = List<List<double>>.generate(
      n + 1,
      (_) => List<double>.filled(m + 1, double.infinity),
    );
    acc[0][0] = 0.0;

    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        final dx = a[i - 1][0] - b[j - 1][0];
        final dy = a[i - 1][1] - b[j - 1][1];
        final cost = dx * dx + dy * dy;
        final best = math.min(
          acc[i - 1][j],
          math.min(acc[i][j - 1], acc[i - 1][j - 1]),
        );
        acc[i][j] = cost + best;
      }
    }
    return math.sqrt(acc[n][m] / (n + m));
  }

  static double sampleDistance(CaptureSample a, CaptureSample b) {
    if (a.strokes.length != b.strokes.length) return double.infinity;
    var sum = 0.0;
    for (var i = 0; i < a.strokes.length; i++) {
      final pa = normalize(resample(a.strokes[i].points));
      final pb = normalize(resample(b.strokes[i].points));
      sum += dtw(pa, pb);
    }
    return sum / a.strokes.length;
  }

  static double againstTemplate(
    CaptureSample sample,
    List<List<List<double>>> template,
  ) {
    if (sample.strokes.length != template.length) return double.infinity;
    var sum = 0.0;
    for (var i = 0; i < template.length; i++) {
      final p = normalize(resample(sample.strokes[i].points));
      sum += dtw(p, template[i]);
    }
    return sum / template.length;
  }
}

class AuthTemplate {
  final String subjectId;
  final String gestureId;
  final String createdAt;
  final int strokeCount;
  final List<List<List<double>>> shapeTemplate;
  final List<List<double>> featureMedians;
  final List<List<double>> featureScales;
  final List<double> interMedian;
  final List<double> interScale;
  final double shapeThreshold;
  final double behaviorThreshold;

  AuthTemplate({
    required this.subjectId,
    required this.gestureId,
    required this.createdAt,
    required this.strokeCount,
    required this.shapeTemplate,
    required this.featureMedians,
    required this.featureScales,
    required this.interMedian,
    required this.interScale,
    required this.shapeThreshold,
    required this.behaviorThreshold,
  });

  AuthTemplate copyWith({
    double? shapeThreshold,
    double? behaviorThreshold,
  }) {
    return AuthTemplate(
      subjectId: subjectId,
      gestureId: gestureId,
      createdAt: createdAt,
      strokeCount: strokeCount,
      shapeTemplate: shapeTemplate,
      featureMedians: featureMedians,
      featureScales: featureScales,
      interMedian: interMedian,
      interScale: interScale,
      shapeThreshold: shapeThreshold ?? this.shapeThreshold,
      behaviorThreshold: behaviorThreshold ?? this.behaviorThreshold,
    );
  }

  static AuthTemplate build({
    required String subjectId,
    required String gestureId,
    required List<CaptureSample> samples,
  }) {
    if (samples.length < 3) {
      throw ArgumentError('至少需要 3 条注册样本');
    }

    final counts = <int, int>{};
    for (final s in samples) {
      counts[s.strokes.length] = (counts[s.strokes.length] ?? 0) + 1;
    }
    final strokeCount = counts.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
    final used = samples.where((s) => s.strokes.length == strokeCount).toList();
    if (used.length < 3) {
      throw ArgumentError('同一笔数的手势样本不足 3 条');
    }

    var medoid = 0;
    var best = double.infinity;
    for (var i = 0; i < used.length; i++) {
      var sum = 0.0;
      for (var j = 0; j < used.length; j++) {
        if (i == j) continue;
        sum += ShapeUtil.sampleDistance(used[i], used[j]);
      }
      if (sum < best) {
        best = sum;
        medoid = i;
      }
    }

    final shapeTemplate = <List<List<double>>>[];
    for (final s in used[medoid].strokes) {
      shapeTemplate.add(ShapeUtil.normalize(ShapeUtil.resample(s.points)));
    }

    final perStroke = List<List<List<double>>>.generate(
      strokeCount,
      (_) => <List<double>>[],
    );
    for (final s in used) {
      for (var i = 0; i < strokeCount; i++) {
        perStroke[i].add(AuthFeatures.stroke(s.strokes[i]));
      }
    }

    final medians = <List<double>>[];
    final scales = <List<double>>[];
    for (var i = 0; i < strokeCount; i++) {
      medians.add(_columnMedian(perStroke[i]));
      scales.add(_columnScale(perStroke[i]));
    }

    final interRows = used.map(AuthFeatures.inter).toList();
    final interMedian = _columnMedian(interRows);
    final interScale = _columnScale(interRows);

    final shapeDistances = <double>[];
    final behaviorDistances = <double>[];
    for (final s in used) {
      shapeDistances.add(_shapeAgainst(s, shapeTemplate));
      behaviorDistances.add(
        _behaviorAgainst(s, medians, scales, interMedian, interScale),
      );
    }

    final shapeThreshold = math.max(_max(shapeDistances) * 1.2, 0.02);
    final behaviorThreshold = math.max(_max(behaviorDistances) * 1.2, 0.5);

    return AuthTemplate(
      subjectId: subjectId,
      gestureId: gestureId,
      createdAt: DateTime.now().toIso8601String(),
      strokeCount: strokeCount,
      shapeTemplate: shapeTemplate,
      featureMedians: medians,
      featureScales: scales,
      interMedian: interMedian,
      interScale: interScale,
      shapeThreshold: shapeThreshold,
      behaviorThreshold: behaviorThreshold,
    );
  }

  AuthResult verify(CaptureSample sample) {
    if (sample.strokes.length != strokeCount) {
      return AuthResult(
        accepted: false,
        shapeDistance: double.infinity,
        shapeThreshold: shapeThreshold,
        behaviorDistance: double.infinity,
        behaviorThreshold: behaviorThreshold,
        reason: '笔数不符（应为 $strokeCount 笔）',
      );
    }

    final shapeDistance = _shapeAgainst(sample, shapeTemplate);
    final behaviorDistance = _behaviorAgainst(
      sample,
      featureMedians,
      featureScales,
      interMedian,
      interScale,
    );

    final shapeOk = shapeDistance <= shapeThreshold;
    final behaviorOk = behaviorDistance <= behaviorThreshold;
    final accepted = shapeOk && behaviorOk;

    final reason = !shapeOk
        ? '形状不匹配'
        : (!behaviorOk ? '行为不像本人' : '通过');

    return AuthResult(
      accepted: accepted,
      shapeDistance: shapeDistance,
      shapeThreshold: shapeThreshold,
      behaviorDistance: behaviorDistance,
      behaviorThreshold: behaviorThreshold,
      reason: reason,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'subject_id': subjectId,
        'gesture_id': gestureId,
        'created_at': createdAt,
        'stroke_count': strokeCount,
        'shape_template': shapeTemplate,
        'feature_medians': featureMedians,
        'feature_scales': featureScales,
        'inter_median': interMedian,
        'inter_scale': interScale,
        'shape_threshold': shapeThreshold,
        'behavior_threshold': behaviorThreshold,
      };

  factory AuthTemplate.fromJson(Map<String, dynamic> json) {
    return AuthTemplate(
      subjectId: '${json['subject_id']}',
      gestureId: '${json['gesture_id']}',
      createdAt: '${json['created_at']}',
      strokeCount: (json['stroke_count'] as num).toInt(),
      shapeTemplate: _tensor(json['shape_template']),
      featureMedians: _matrix(json['feature_medians']),
      featureScales: _matrix(json['feature_scales']),
      interMedian: _doubles(json['inter_median']),
      interScale: _doubles(json['inter_scale']),
      shapeThreshold: (json['shape_threshold'] as num).toDouble(),
      behaviorThreshold: (json['behavior_threshold'] as num).toDouble(),
    );
  }
}

class AuthResult {
  final bool accepted;
  final double shapeDistance;
  final double shapeThreshold;
  final double behaviorDistance;
  final double behaviorThreshold;
  final String reason;

  const AuthResult({
    required this.accepted,
    required this.shapeDistance,
    required this.shapeThreshold,
    required this.behaviorDistance,
    required this.behaviorThreshold,
    required this.reason,
  });

  double get shapeRatio =>
      shapeThreshold > 0 ? shapeDistance / shapeThreshold : double.infinity;

  double get behaviorRatio => behaviorThreshold > 0
      ? behaviorDistance / behaviorThreshold
      : double.infinity;
}

double _shapeAgainst(
  CaptureSample sample,
  List<List<List<double>>> template,
) {
  return ShapeUtil.againstTemplate(sample, template);
}

double _behaviorAgainst(
  CaptureSample sample,
  List<List<double>> medians,
  List<List<double>> scales,
  List<double> interMedian,
  List<double> interScale,
) {
  if (sample.strokes.length != medians.length) return double.infinity;

  final durations = sample.strokes
      .map((s) => math.max(s.durationMs / 1000.0, 1e-6))
      .toList();
  final total = durations.fold<double>(0.0, (a, b) => a + b);

  var strokeDistance = 0.0;
  for (var i = 0; i < sample.strokes.length; i++) {
    final f = AuthFeatures.stroke(sample.strokes[i]);
    var sum = 0.0;
    for (var d = 0; d < AuthFeatures.dimension; d++) {
      final scale = scales[i][d].abs() < 1e-9 ? 1.0 : scales[i][d];
      final z = ((f[d] - medians[i][d]) / scale).clamp(-5.0, 5.0);
      sum += z * z;
    }
    final distance = math.sqrt(sum / AuthFeatures.dimension);
    strokeDistance += distance * (durations[i] / total);
  }

  final inter = AuthFeatures.inter(sample);
  var interSum = 0.0;
  for (var i = 0; i < inter.length; i++) {
    final scale = interScale[i].abs() < 1e-9 ? 1.0 : interScale[i];
    final z = ((inter[i] - interMedian[i]) / scale).clamp(-5.0, 5.0);
    interSum += z * z;
  }
  final interDistance = math.sqrt(interSum / inter.length);
  return 0.8 * strokeDistance + 0.2 * interDistance;
}

List<double> _columnMedian(List<List<double>> rows) {
  if (rows.isEmpty) return <double>[];
  final columns = rows.first.length;
  final out = <double>[];
  for (var c = 0; c < columns; c++) {
    final values = rows.map((r) => r[c]).toList()..sort();
    out.add(_median(values));
  }
  return out;
}

List<double> _columnScale(List<List<double>> rows) {
  if (rows.isEmpty) return <double>[];
  final columns = rows.first.length;
  final out = <double>[];
  for (var c = 0; c < columns; c++) {
    final values = rows.map((r) => r[c]).toList();
    final sorted = [...values]..sort();
    final q25 = _percentile(sorted, 0.25);
    final q75 = _percentile(sorted, 0.75);
    final iqr = q75 - q25;
    final sd = _std(values);
    out.add(iqr.abs() > 1e-9 ? iqr : (sd.abs() > 1e-9 ? sd : 1.0));
  }
  return out;
}

double _mean(List<double> values) {
  if (values.isEmpty) return 0.0;
  return values.fold<double>(0.0, (a, b) => a + b) / values.length;
}

double _std(List<double> values) {
  if (values.length < 2) return 0.0;
  final m = _mean(values);
  var sum = 0.0;
  for (final v in values) {
    sum += (v - m) * (v - m);
  }
  return math.sqrt(sum / (values.length - 1));
}

double _median(List<double> sorted) {
  if (sorted.isEmpty) return 0.0;
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2.0;
}

double _percentile(List<double> sorted, double p) {
  if (sorted.isEmpty) return 0.0;
  if (sorted.length == 1) return sorted.first;
  final pos = (sorted.length - 1) * p;
  final low = pos.floor();
  final high = pos.ceil();
  if (low == high) return sorted[low];
  final f = pos - low;
  return sorted[low] * (1 - f) + sorted[high] * f;
}

double _min(List<double> values) {
  if (values.isEmpty) return 0.0;
  return values.reduce(math.min);
}

double _max(List<double> values) {
  if (values.isEmpty) return 0.0;
  return values.reduce(math.max);
}

double _slope(List<double> x, List<double> y) {
  final n = math.min(x.length, y.length);
  if (n < 2) return 0.0;
  final mx = _mean(x.sublist(0, n));
  final my = _mean(y.sublist(0, n));
  var num = 0.0;
  var den = 0.0;
  for (var i = 0; i < n; i++) {
    final dx = x[i] - mx;
    num += dx * (y[i] - my);
    den += dx * dx;
  }
  return den.abs() < 1e-12 ? 0.0 : num / den;
}

double _corr(List<double> a, List<double> b) {
  final n = math.min(a.length, b.length);
  if (n < 3) return 0.0;
  final ma = _mean(a.sublist(0, n));
  final mb = _mean(b.sublist(0, n));
  var num = 0.0;
  var da = 0.0;
  var db = 0.0;
  for (var i = 0; i < n; i++) {
    final x = a[i] - ma;
    final y = b[i] - mb;
    num += x * y;
    da += x * x;
    db += y * y;
  }
  if (da < 1e-12 || db < 1e-12) return 0.0;
  return num / math.sqrt(da * db);
}

List<double> _doubles(dynamic value) {
  return (value as List<dynamic>)
      .map((e) => (e as num).toDouble())
      .toList();
}

List<List<double>> _matrix(dynamic value) {
  return (value as List<dynamic>)
      .map((row) => _doubles(row))
      .toList();
}

List<List<List<double>>> _tensor(dynamic value) {
  return (value as List<dynamic>)
      .map((stroke) => _matrix(stroke))
      .toList();
}
