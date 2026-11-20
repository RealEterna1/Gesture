import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'condition_labels.dart';
import 'live_curve.dart';
import 'models.dart';
import 'painter.dart';
import 'store.dart';

class CaptureScreen extends StatefulWidget {
  final String subjectId;
  final String gestureId;
  final String condition;
  final String notes;
  final Map<String, dynamic> device;
  final bool saveSample;
  final bool popOnSave;
  final bool showSummary;
  final String finishLabel;

  const CaptureScreen({
    super.key,
    required this.subjectId,
    required this.gestureId,
    required this.condition,
    this.notes = '',
    required this.device,
    this.saveSample = true,
    this.popOnSave = false,
    this.showSummary = true,
    this.finishLabel = '完成并保存',
  });

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final List<Stroke> _strokes = [];
  List<TouchPoint> _current = [];
  int? _activePointer;
  Duration? _sampleStart;
  bool _multiTouch = false;
  bool _saving = false;
  String _inputMode = 'stylus';
  String? _activeKind;
  int _sampleIndex = 0;
  Size _canvasSize = Size.zero;
  int _lastNotifyMs = 0;
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);
  late final String _sessionId;

  @override
  void initState() {
    super.initState();
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    _sessionId = '${widget.subjectId}_${t.year}${two(t.month)}${two(t.day)}'
        '_${two(t.hour)}${two(t.minute)}';
  }

  @override
  void dispose() {
    _revision.dispose();
    super.dispose();
  }

  TouchPoint _pointFrom(PointerEvent e) {
    final start = _sampleStart ?? e.timeStamp;
    return TouchPoint(
      t: (e.timeStamp - start).inMicroseconds / 1000.0,
      rawUs: e.timeStamp.inMicroseconds,
      x: e.localPosition.dx,
      y: e.localPosition.dy,
      pressure: e.pressure,
      pressureMin: e.pressureMin,
      pressureMax: e.pressureMax,
      tilt: e.tilt,
    );
  }

  void _bump({bool throttle = false}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (throttle && now - _lastNotifyMs < 33) return;
    _lastNotifyMs = now;
    _revision.value++;
  }

  String _kindName(PointerDeviceKind kind) {
    switch (kind) {
      case PointerDeviceKind.stylus:
      case PointerDeviceKind.invertedStylus:
        return 'stylus';
      case PointerDeviceKind.touch:
        return 'touch';
      default:
        return kind.name;
    }
  }

  void _onDown(PointerDownEvent e) {
    if (_saving) return;
    final kind = _kindName(e.kind);
    if (kind != 'stylus' && kind != 'touch') return;
    _inputMode = kind;
    if (_activePointer != null) {
      _multiTouch = true;
      return;
    }
    _activePointer = e.pointer;
    _activeKind = kind;
    _sampleStart ??= e.timeStamp;
    _current = [_pointFrom(e)];
    _bump();
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _activePointer) return;
    _current.add(_pointFrom(e));
    _bump(throttle: true);
  }

  void _onUp(PointerUpEvent e) {
    if (e.pointer != _activePointer) return;
    final pts = [..._current, _pointFrom(e)];
    _strokes.add(
      Stroke(
        index: _strokes.length,
        startT: pts.first.t,
        endT: pts.last.t,
        points: pts,
        kind: _activeKind ?? 'unknown',
      ),
    );
    _current = [];
    _activePointer = null;
    _activeKind = null;
    _bump();
  }

  void _onCancel(PointerCancelEvent e) {
    if (e.pointer != _activePointer) return;
    if (_current.isNotEmpty) {
      _strokes.add(
        Stroke(
          index: _strokes.length,
          startT: _current.first.t,
          endT: _current.last.t,
          points: _current,
          cancelled: true,
          kind: _activeKind ?? 'unknown',
        ),
      );
    }
    _current = [];
    _activePointer = null;
    _activeKind = null;
    _bump();
    _toast('触摸被系统取消，该笔已标记');
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _current = [];
      _activePointer = null;
      _activeKind = null;
      _sampleStart = null;
      _multiTouch = false;
    });
    _bump();
  }

  void _undo() {
    setState(() {
      if (_current.isNotEmpty) {
        _current = [];
        _activePointer = null;
        _activeKind = null;
      } else if (_strokes.isNotEmpty) {
        _strokes.removeLast();
      }
      if (_strokes.isEmpty) _sampleStart = null;
    });
    _bump();
  }

  Future<void> _finish() async {
    if (_saving) return;
    if (_strokes.isEmpty) {
      _toast('请先在画布上画出手势');
      return;
    }
    setState(() => _saving = true);
    try {
      final stats = computeStats(_strokes, multiTouch: _multiTouch);
      final mq = MediaQuery.of(context);
      final sample = CaptureSample(
        subjectId: widget.subjectId,
        gestureId: widget.gestureId,
        condition: widget.condition,
        notes: widget.notes,
        sampleIndex: _sampleIndex + 1,
        sessionId: _sessionId,
        capturedAt: DateTime.now().toIso8601String(),
        device: widget.device,
        canvas: {
          'width': double.parse(_canvasSize.width.toStringAsFixed(2)),
          'height': double.parse(_canvasSize.height.toStringAsFixed(2)),
          'device_pixel_ratio': double.parse(mq.devicePixelRatio.toString()),
          'refresh_rate_hz':
              double.parse(View.of(context).display.refreshRate.toString()),
        },
        inputMode: _inputMode,
        multiTouchDetected: _multiTouch,
        strokes: _strokes,
        stats: stats,
      );
      if (widget.saveSample) {
        await SampleStore.save(sample);
      }
      if (!mounted) return;
      if (widget.showSummary) {
        await _showSummary(sample);
        if (!mounted) return;
      }
      if (widget.popOnSave) {
        Navigator.of(context).pop(sample);
        return;
      }
      setState(() {
        _strokes.clear();
        _current = [];
        _sampleStart = null;
        _activePointer = null;
        _activeKind = null;
        _multiTouch = false;
        _sampleIndex += 1;
      });
      _bump();
    } catch (err) {
      _toast('保存失败：$err');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showSummary(CaptureSample sample) {
    final s = sample.stats;
    final warnings = <String>[
      if (s.pressureDistinct <= 1)
        '压力值只有 1 个取值（${s.pressureMax.toStringAsFixed(3)}），'
            '可能是设备或笔不支持真实压感，压力特征将不可用',
      if (s.sampleRateHz < 60)
        '采样率仅 ${s.sampleRateHz.toStringAsFixed(0)} Hz，偏低',
      if (sample.multiTouchDetected) '检测到多指触摸，该样本可能不可用',
      if (sample.strokes.any((e) => e.cancelled)) '存在被系统取消的笔画',
    ];

    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('第 ${sample.sampleIndex} 次采集已保存'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _kv('笔画数', '${s.strokeCount}'),
              _kv('采样点', '${s.pointCount}'),
              _kv('输入来源', _strokeKinds(sample)),
              _kv('时长', '${(s.durationMs / 1000).toStringAsFixed(2)} s'),
              _kv('采样率', '${s.sampleRateHz.toStringAsFixed(0)} Hz'),
              _kv(
                '压力范围',
                '${s.pressureMin.toStringAsFixed(3)} ~ '
                    '${s.pressureMax.toStringAsFixed(3)} '
                    '(${s.pressureDistinct} 个取值)',
              ),
              _kv('压力标准差', s.pressureStd.toStringAsFixed(4)),
              _kv('平均速度', '${s.speedMeanPxPerMs.toStringAsFixed(3)} px/ms'),
              const SizedBox(height: 12),
              if (warnings.isEmpty)
                const Text('数据看起来正常', style: TextStyle(color: Colors.greenAccent))
              else
                ...warnings.map(
                  (w) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '· $w',
                      style: const TextStyle(color: Colors.orangeAccent),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('继续下一个'),
          ),
        ],
      ),
    );
  }

  String _strokeKinds(CaptureSample sample) {
    final kinds = sample.strokes
        .map((s) => s.kind == 'stylus' ? '笔' : (s.kind == 'touch' ? '手指' : s.kind))
        .toSet()
        .join('+');
    final mode = sample.inputMode == 'touch'
        ? '手指'
        : (sample.inputMode == 'stylus' ? '手写笔' : '笔/指均可');
    return '$kinds（$mode）';
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 78,
              child: Text(k, style: const TextStyle(color: Colors.white54)),
            ),
            Expanded(child: Text(v)),
          ],
        ),
      );

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.subjectId} · ${widget.gestureId}'),
            Text(
              '第 ${_sampleIndex + 1} 次 · '
              '${kConditionLabels[widget.condition] ?? widget.condition}',
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _strokes.isEmpty && _current.isEmpty ? null : _clear,
            child: const Text('清空'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _statusBar(),
            LiveCurve(
              strokes: _strokes,
              current: _current,
              revision: _revision,
            ),
            const SizedBox(height: 4),
            Expanded(child: _canvas()),
            _actions(),
          ],
        ),
      ),
    );
  }

  Widget _statusBar() {
    return ListenableBuilder(
      listenable: _revision,
      builder: (context, _) {
        final all = [
          ..._strokes.expand((s) => s.points),
          ..._current,
        ];
        final duration = all.isEmpty ? 0.0 : all.last.t - all.first.t;
        final rate = duration > 0 ? (all.length - 1) / duration * 1000 : 0.0;
        final pressure = all.isEmpty ? 0.0 : all.last.pressure;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _pill('笔画 ${_strokes.length}'),
                _pill('点 ${all.length}'),
                _pill('${(duration / 1000).toStringAsFixed(1)}s'),
                _pill('${rate.toStringAsFixed(0)}Hz'),
                _pill('P ${pressure.toStringAsFixed(2)}'),
                _pill(_activeKind == null
                    ? '笔/指'
                    : (_activeKind == 'stylus' ? '笔' : '手指')),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _pill(String text) => Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 11, color: Colors.white70),
        ),
      );

  Widget _canvas() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1D24),
            border: Border.all(color: Colors.white10),
            borderRadius: BorderRadius.circular(16),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              _canvasSize = constraints.biggest;
              return Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onDown,
                onPointerMove: _onMove,
                onPointerUp: _onUp,
                onPointerCancel: _onCancel,
                child: CustomPaint(
                  painter: GesturePainter(
                    strokes: _strokes,
                    current: _current,
                    revision: _revision,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  child: const SizedBox.expand(),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _actions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
        children: [
          OutlinedButton(
            onPressed: (_strokes.isEmpty && _current.isEmpty) ? null : _undo,
            child: const Text('撤销一笔'),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: _saving ? null : _finish,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(widget.finishLabel),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
