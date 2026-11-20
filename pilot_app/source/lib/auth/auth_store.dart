import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models.dart';
import 'auth_core.dart';

/// 端上模板存储：`documents/templates/subject_gesture.json`
class AuthTemplateStore {
  static Future<Directory> _dir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/templates');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static String _safe(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');

  static Future<File> _file(String subject, String gesture) async {
    final dir = await _dir();
    return File('${dir.path}/${_safe(subject)}_${_safe(gesture)}.json');
  }

  static Future<void> save(AuthTemplate template) async {
    final file = await _file(template.subjectId, template.gestureId);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(template.toJson()),
    );
  }

  static Future<AuthTemplate?> load(String subject, String gesture) async {
    final file = await _file(subject, gesture);
    if (!await file.exists()) return null;
    try {
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return AuthTemplate.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> exists(String subject, String gesture) async {
    final file = await _file(subject, gesture);
    return file.exists();
  }

  static Future<void> delete(String subject, String gesture) async {
    final file = await _file(subject, gesture);
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<List<AuthTemplate>> list() async {
    final dir = await _dir();
    final templates = <AuthTemplate>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final map =
            jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        templates.add(AuthTemplate.fromJson(map));
      } catch (_) {
        // 跳过损坏模板
      }
    }
    templates.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return templates;
  }

  static Future<void> deleteAll() async {
    final dir = await _dir();
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        try {
          await entity.delete();
        } catch (_) {
          // 单个失败不阻塞
        }
      }
    }
  }
}

/// 一次验证记录，用于统计端上 FAR/FRR 和与离线结果对照。
class VerificationRecord {
  final String subjectId;
  final String gestureId;
  final String timestamp;
  final String inputMode;
  final String condition;
  final String performerId;
  final bool accepted;
  final String reason;
  final int strokeCount;
  final int pressureDistinct;
  final double durationMs;
  final double shapeDistance;
  final double shapeThreshold;
  final double behaviorDistance;
  final double behaviorThreshold;
  final Map<String, dynamic>? rawSample;

  const VerificationRecord({
    required this.subjectId,
    required this.gestureId,
    required this.timestamp,
    required this.inputMode,
    required this.condition,
    required this.performerId,
    required this.accepted,
    required this.reason,
    required this.strokeCount,
    required this.pressureDistinct,
    required this.durationMs,
    required this.shapeDistance,
    required this.shapeThreshold,
    required this.behaviorDistance,
    required this.behaviorThreshold,
    this.rawSample,
  });

  factory VerificationRecord.fromSample(
    CaptureSample sample,
    AuthResult result, {
    required String condition,
    String performerId = '',
    String? accountSubjectId,
  }) {
    return VerificationRecord(
      subjectId: accountSubjectId ?? sample.subjectId,
      gestureId: sample.gestureId,
      timestamp: DateTime.now().toIso8601String(),
      inputMode: sample.inputMode,
      condition: condition,
      performerId: performerId,
      accepted: result.accepted,
      reason: result.reason,
      strokeCount: sample.strokes.length,
      pressureDistinct: sample.stats.pressureDistinct,
      durationMs: sample.stats.durationMs,
      shapeDistance: result.shapeDistance,
      shapeThreshold: result.shapeThreshold,
      behaviorDistance: result.behaviorDistance,
      behaviorThreshold: result.behaviorThreshold,
      rawSample: sample.toJson(),
    );
  }

  double get shapeRatio =>
      shapeThreshold > 0 ? shapeDistance / shapeThreshold : double.infinity;

  double get behaviorRatio => behaviorThreshold > 0
      ? behaviorDistance / behaviorThreshold
      : double.infinity;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'subject_id': subjectId,
        'gesture_id': gestureId,
        'timestamp': timestamp,
        'input_mode': inputMode,
        'condition': condition,
        'performer_id': performerId,
        'accepted': accepted,
        'reason': reason,
        'stroke_count': strokeCount,
        'pressure_distinct': pressureDistinct,
        'duration_ms': durationMs,
        'shape_distance': shapeDistance,
        'shape_threshold': shapeThreshold,
        'behavior_distance': behaviorDistance,
        'behavior_threshold': behaviorThreshold,
        'raw_sample': rawSample,
      };

  factory VerificationRecord.fromJson(Map<String, dynamic> json) {
    return VerificationRecord(
      subjectId: '${json['subject_id']}',
      gestureId: '${json['gesture_id']}',
      timestamp: '${json['timestamp']}',
      inputMode: '${json['input_mode']}',
      condition: '${json['condition'] ?? 'genuine'}',
      performerId: '${json['performer_id'] ?? ''}',
      accepted: json['accepted'] == true,
      reason: '${json['reason']}',
      strokeCount: (json['stroke_count'] as num?)?.toInt() ?? 0,
      pressureDistinct: (json['pressure_distinct'] as num?)?.toInt() ?? 0,
      durationMs: (json['duration_ms'] as num?)?.toDouble() ?? 0,
      shapeDistance: (json['shape_distance'] as num?)?.toDouble() ?? 0,
      shapeThreshold: (json['shape_threshold'] as num?)?.toDouble() ?? 0,
      behaviorDistance: (json['behavior_distance'] as num?)?.toDouble() ?? 0,
      behaviorThreshold: (json['behavior_threshold'] as num?)?.toDouble() ?? 0,
      rawSample: json['raw_sample'] is Map<String, dynamic>
          ? json['raw_sample'] as Map<String, dynamic>
          : null,
    );
  }
}

/// 验证日志：JSONL 追加写，便于长期积累和导出。
class AuthLogStore {
  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}_'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  static Future<File> _file() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/auth_logs');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/verification_logs.jsonl');
  }

  static Future<void> append(VerificationRecord record) async {
    final file = await _file();
    await file.writeAsString(
      '${jsonEncode(record.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  static Future<List<VerificationRecord>> list() async {
    final file = await _file();
    if (!await file.exists()) return <VerificationRecord>[];
    final records = <VerificationRecord>[];
    for (final line in await file.readAsLines()) {
      if (line.trim().isEmpty) continue;
      try {
        records.add(
          VerificationRecord.fromJson(
            jsonDecode(line) as Map<String, dynamic>,
          ),
        );
      } catch (_) {
        // 跳过损坏行
      }
    }
    return records;
  }

  static Future<int> count() async => (await list()).length;

  static Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// 删除指定的一条记录（按 timestamp + 被试 + 手势匹配）。
  static Future<void> delete(VerificationRecord target) async {
    final file = await _file();
    if (!await file.exists()) return;
    final lines = await file.readAsLines();
    final kept = <String>[];
    var removed = false;
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      if (!removed) {
        try {
          final record = VerificationRecord.fromJson(
            jsonDecode(line) as Map<String, dynamic>,
          );
          if (record.timestamp == target.timestamp &&
              record.subjectId == target.subjectId &&
              record.gestureId == target.gestureId) {
            removed = true;
            continue;
          }
        } catch (_) {
          // 无法解析的行保留
        }
      }
      kept.add(line);
    }
    await file.writeAsString(kept.isEmpty ? '' : '${kept.join('\n')}\n');
  }

  static Future<File> export() async {
    final records = await list();
    final root = await getApplicationDocumentsDirectory();
    final out = File(
      '${root.path}/verification_logs_${_stamp(DateTime.now())}.json',
    );
    await out.writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'exported_at': DateTime.now().toIso8601String(),
        'count': records.length,
        'records': records.map((r) => r.toJson()).toList(),
      }),
    );
    return out;
  }
}
