import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 原生层自检：列出触摸设备支持的所有轴，并读取最近一次触摸的原始
/// MotionEvent 压力/接触面积，用于判断压力恒定是硬件限制还是采集层问题。
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  static const _channel = MethodChannel('gesture_collector/diagnostics');

  Map<String, dynamic>? _caps;
  List<Map<String, dynamic>> _raw = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final capsJson = await _channel.invokeMethod<String>('capabilities');
      final rawJson = await _channel.invokeMethod<String>('rawSamples');
      final caps = capsJson == null
          ? <String, dynamic>{}
          : jsonDecode(capsJson) as Map<String, dynamic>;
      final raw = rawJson == null
          ? <String, dynamic>{}
          : jsonDecode(rawJson) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _caps = caps;
        _raw = (raw['samples'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  String _range(Map<String, dynamic> axes, String axis) {
    final v = axes[axis];
    if (v is! Map) return '不支持';
    return '${v['min']} ~ ${v['max']}';
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(k, style: const TextStyle(color: Colors.white54)),
            ),
            Expanded(child: Text(v)),
          ],
        ),
      );

  Future<void> _startProbe() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const _ProbePage()),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final devices =
        (_caps?['devices'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

    final pressures = _raw
        .map((e) => (e['p'] as num?)?.toDouble() ?? 0)
        .toList();
    final times = _raw.map((e) => (e['t'] as num?)?.toInt() ?? 0).toList();
    final distinct =
        pressures.map((p) => p.toStringAsFixed(4)).toSet().length;
    final duration = times.length < 2 ? 0 : times.last - times.first;
    final rate =
        duration > 0 ? (times.length - 1) / duration * 1000 : 0.0;
    final histCount =
        _raw.fold<int>(0, (a, e) => a + ((e['hist'] as num?)?.toInt() ?? 0));

    return Scaffold(
      appBar: AppBar(
        title: const Text('设备自检'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (_error != null)
                  _section('错误', [Text(_error!)]),
                FilledButton.icon(
                  onPressed: _startProbe,
                  icon: const Icon(Icons.touch_app),
                  label: const Text('开始手势探测'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                ),
                const SizedBox(height: 12),
                _section('设备', [
                  _kv(
                    '机型',
                    '${_caps?['manufacturer'] ?? '-'} '
                        '${_caps?['model'] ?? '-'}',
                  ),
                  _kv('Android API', '${_caps?['sdk'] ?? '-'}'),
                ]),
                for (final d in devices)
                  _section('触摸设备：${d['name']}', [
                    _kv('deviceId', '${d['id']}'),
                    _kv('sources', '0x${d['sources']}'),
                    _kv('触摸屏', d['touchscreen'] == true ? '是' : '否'),
                    const Divider(height: 16),
                    _kv(
                      'AXIS_PRESSURE',
                      _range(d['axes'] as Map<String, dynamic>, 'AXIS_PRESSURE'),
                    ),
                    _kv(
                      'AXIS_TILT',
                      _range(d['axes'] as Map<String, dynamic>, 'AXIS_TILT'),
                    ),
                    _kv(
                      '轴总数',
                      '${(d['axes'] as Map).length}',
                    ),
                  ]),
                _section('最近一次触摸的原始事件', [
                  _kv('事件数', '${_raw.length}'),
                  _kv('批量采样点', '$histCount'),
                  _kv(
                    '原生压力',
                    pressures.isEmpty
                        ? '无数据（先画一笔再刷新）'
                        : '${pressures.reduce((a, b) => a < b ? a : b).toStringAsFixed(3)}'
                            ' ~ '
                            '${pressures.reduce((a, b) => a > b ? a : b).toStringAsFixed(3)}'
                            '（$distinct 个取值）',
                  ),
                  _kv('事件采样率', '${rate.toStringAsFixed(0)} Hz'),
                  const SizedBox(height: 8),
                  if (pressures.isNotEmpty)
                    Text(
                      distinct <= 1
                          ? '原生层压力同样恒定，该设备没有压力轴（硬件限制）'
                          : '原生层压力有变化，说明设备支持压力采集',
                      style: TextStyle(
                        color: distinct <= 1
                            ? Colors.orangeAccent
                            : Colors.greenAccent,
                      ),
                    ),
                ]),
                const SizedBox(height: 4),
                Text(
                  '用法：回到采集页用手指画一笔，再回到这里点刷新，'
                  '即可对比原生层与 App 显示的压力值。',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.white38),
                ),
              ],
            ),
    );
  }
}

/// 全屏探测画布：这里没有滚动，所有触摸都是纯粹的手势触摸。
class _ProbePage extends StatefulWidget {
  const _ProbePage();

  @override
  State<_ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<_ProbePage> {
  final List<List<Offset>> _strokes = [];
  List<Offset> _current = [];
  int? _pointer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('手势探测'),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              _strokes.clear();
              _current = [];
              _pointer = null;
            }),
            child: const Text('清空'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                '用不同力度画一条长线（持续 0.5 秒以上），返回上一页即可看到'
                '原生层记录的压力范围。',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1D24),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                clipBehavior: Clip.antiAlias,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) {
                    _pointer = e.pointer;
                    setState(() => _current = [e.localPosition]);
                  },
                  onPointerMove: (e) {
                    if (e.pointer != _pointer) return;
                    setState(() => _current = [..._current, e.localPosition]);
                  },
                  onPointerUp: (e) {
                    if (e.pointer != _pointer) return;
                    setState(() {
                      _strokes.add([..._current, e.localPosition]);
                      _current = [];
                      _pointer = null;
                    });
                  },
                  child: CustomPaint(
                    painter: _InkPainter(strokes: _strokes, current: _current),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InkPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final List<Offset> current;

  _InkPainter({required this.strokes, required this.current});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF8AA5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final line in [...strokes, current]) {
      if (line.isEmpty) continue;
      if (line.length == 1) {
        canvas.drawCircle(line.first, 2, paint);
        continue;
      }
      final path = Path()..moveTo(line.first.dx, line.first.dy);
      for (var i = 1; i < line.length; i++) {
        path.lineTo(line[i].dx, line[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _InkPainter old) => true;
}
