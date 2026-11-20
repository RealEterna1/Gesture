import 'package:flutter/material.dart';

import 'auth/auth_core.dart';
import 'auth/auth_store.dart';
import 'capture_screen.dart';
import 'models.dart';

/// 端上注册：连续采集 N 次本人手势，生成并保存模板。
class EnrollScreen extends StatefulWidget {
  final String subjectId;
  final String gestureId;
  final Map<String, dynamic> device;

  const EnrollScreen({
    super.key,
    required this.subjectId,
    required this.gestureId,
    required this.device,
  });

  @override
  State<EnrollScreen> createState() => _EnrollScreenState();
}

class _EnrollScreenState extends State<EnrollScreen> {
  static const int _target = 10;
  final List<CaptureSample> _samples = [];
  AuthTemplate? _template;
  bool _busy = false;

  Future<void> _capture() async {
    if (_busy || _template != null) return;
    final sample = await Navigator.of(context).push<CaptureSample>(
      MaterialPageRoute(
        builder: (_) => CaptureScreen(
          subjectId: widget.subjectId,
          gestureId: widget.gestureId,
          condition: 'genuine',
          device: widget.device,
          saveSample: false,
          popOnSave: true,
          showSummary: false,
          finishLabel: '完成本次',
        ),
      ),
    );
    if (sample == null || !mounted) return;
    setState(() => _samples.add(sample));
    if (_samples.length >= _target) {
      await _buildTemplate();
    }
  }

  Future<void> _buildTemplate() async {
    setState(() => _busy = true);
    try {
      final template = AuthTemplate.build(
        subjectId: widget.subjectId,
        gestureId: widget.gestureId,
        samples: _samples,
      );
      await AuthTemplateStore.save(template);
      if (!mounted) return;
      setState(() => _template = template);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('生成模板失败：$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final template = _template;
    return Scaffold(
      appBar: AppBar(title: const Text('注册模板')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Text(
              '${widget.subjectId} · ${widget.gestureId}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              '连续采 $_target 次本人手势，系统会生成形状模板和行为模型。'
              '每次都必须用同一支笔，笔数保持一致。',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
            ),
            const SizedBox(height: 20),
            LinearProgressIndicator(value: _samples.length / _target),
            const SizedBox(height: 8),
            Text(
              '${_samples.length} / $_target',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            if (template == null)
              FilledButton.icon(
                onPressed: (_busy || _samples.length >= _target) ? null : _capture,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.draw_outlined),
                label: Text(
                  _busy ? '生成模板中…' : '采集第 ${_samples.length + 1} 次',
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
            if (template != null) ...[
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('模板已生成', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      _kv('手势笔数', '${template.strokeCount}'),
                      _kv(
                        '形状阈值',
                        template.shapeThreshold.toStringAsFixed(4),
                      ),
                      _kv(
                        '行为阈值',
                        template.behaviorThreshold.toStringAsFixed(4),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '阈值由注册样本自动估计。样本越多、越自然，阈值越稳。',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.white54),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                child: const Text('完成'),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              '提示：注册样本不会进入“样本列表”，只用于生成模板；'
              '如果要保留原始数据，请回首页用“开始采集”。',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              child: Text(k, style: const TextStyle(color: Colors.white54)),
            ),
            Expanded(child: Text(v)),
          ],
        ),
      );
}
