import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

class SampleStore {
  static Future<Directory> samplesDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/samples');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}_'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  static Future<File> save(CaptureSample sample) async {
    final dir = await samplesDir();
    final name = '${sample.subjectId}_${sample.gestureId}_'
        '${sample.condition}_${_stamp(DateTime.now())}_'
        's${sample.sampleIndex}.json';
    final file = File('${dir.path}/$name');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(sample.toJson()),
    );
    return file;
  }

  static Future<List<File>> listFiles() async {
    final dir = await samplesDir();
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.json'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  static Future<Map<String, dynamic>> readMeta(File f) async {
    final text = await f.readAsString();
    final map = jsonDecode(text) as Map<String, dynamic>;
    return map;
  }

  static Future<int> count() async => (await listFiles()).length;

  /// 删除全部样本，返回成功删除的数量。
  static Future<int> deleteAll() async {
    final files = await listFiles();
    var removed = 0;
    for (final f in files) {
      try {
        await f.delete();
        removed++;
      } catch (_) {
        // 单个文件删除失败不阻塞其余文件
      }
    }
    return removed;
  }

  /// 把所有样本合并成一个 JSON 文件，便于一次性导出分析。
  static Future<File> exportAll() async {
    final files = await listFiles();
    final samples = <Map<String, dynamic>>[];
    for (final f in files) {
      samples.add(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    }
    final root = await getApplicationDocumentsDirectory();
    final out = File(
      '${root.path}/gesture_samples_${_stamp(DateTime.now())}.json',
    );
    await out.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'exported_at': DateTime.now().toIso8601String(),
        'sample_count': samples.length,
        'samples': samples,
      }),
    );
    return out;
  }

  static Future<Map<String, dynamic>> deviceInfo() async {
    final info = await DeviceInfoPlugin().androidInfo;
    return {
      'platform': 'android',
      'manufacturer': info.manufacturer,
      'model': info.model,
      'device': info.device,
      'board': info.board,
      'hardware': info.hardware,
      'android_release': info.version.release,
      'sdk_int': info.version.sdkInt,
      'app_version': '1.0.0',
    };
  }
}
