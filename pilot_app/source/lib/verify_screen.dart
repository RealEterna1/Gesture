import 'package:flutter/material.dart';

import 'auth/auth_core.dart';
import 'auth/auth_store.dart';
import 'capture_screen.dart';
import 'models.dart';

/// 端上验证：采一次手势，过形状门和行为层，显示分数与判定。
class VerifyScreen extends StatefulWidget {
  final String subjectId;
  final String gestureId;
  final Map<String, dynamic> device;

  const VerifyScreen({
    super.key,
    required this.subjectId,
    required this.gestureId,
    required this.device,
  });

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  AuthTemplate? _template;
  AuthResult? _result;
  bool _loading = true;
  bool _busy = false;
  String _condition = 'genuine';
  final _performer = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _performer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final template = await AuthTemplateStore.load(
      widget.subjectId,
      widget.gestureId,
    );
    if (!mounted) return;
    setState(() {
      _template = template;
      _loading = false;
    });
  }

  Future<void> _verify() async {
    final template = _template;
    if (template == null || _busy) return;
    if (_condition == 'mimic' && _performer.text.trim().isEmpty) {
      _toast('请填写测试者编号（谁在画）');
      return;
    }
    setState(() => _busy = true);
    final performer = _condition == 'mimic'
        ? _performer.text.trim()
        : widget.subjectId;
    final sample = await Navigator.of(context).push<CaptureSample>(
      MaterialPageRoute(
        builder: (_) => CaptureScreen(
          subjectId: performer,
          gestureId: widget.gestureId,
          condition: _condition,
          notes: _condition == 'mimic' ? 'target=${widget.subjectId}' : '',
          device: widget.device,
          saveSample: false,
          popOnSave: true,
          showSummary: false,
          finishLabel: '完成验证',
        ),
      ),
    );
    if (!mounted) return;
    if (sample != null) {
      final result = template.verify(sample);
      setState(() => _result = result);
      try {
        await AuthLogStore.append(
          VerificationRecord.fromSample(
            sample,
            result,
            condition: _condition,
            performerId: performer,
            accountSubjectId: widget.subjectId,
          ),
        );
      } catch (_) {
        // 记录失败不影响本次验证
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final template = _template;
    final result = _result;

    return Scaffold(
      appBar: AppBar(title: const Text('验证')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : template == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.info_outline, size: 40),
                          const SizedBox(height: 12),
                          Text(
                            '还没有 ${widget.subjectId} · ${widget.gestureId} 的模板',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '请先回首页点击“注册模板”。',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: Colors.white54),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    children: [
                      Text(
                        '${widget.subjectId} · ${widget.gestureId}',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '画一次手势，系统会先过形状门，再比较速度、压力和节奏。',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.white54),
                      ),
                      const SizedBox(height: 16),
                      Text('验证类型', style: theme.textTheme.labelLarge),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'genuine',
                            label: Text('本人验证'),
                          ),
                          ButtonSegment(
                            value: 'mimic',
                            label: Text('冒用测试'),
                          ),
                        ],
                        selected: {_condition},
                        onSelectionChanged: (value) {
                          setState(() => _condition = value.first);
                        },
                      ),
                      if (_condition == 'mimic') ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _performer,
                          decoration: const InputDecoration(
                            labelText: '测试者编号（谁在画）',
                            hintText: '例如 P02',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _busy ? null : _verify,
                        icon: const Icon(Icons.verified_user_outlined),
                        label: Text(_busy ? '验证中…' : '开始验证'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                      ),
                      if (result != null) ...[
                        const SizedBox(height: 20),
                        _resultCard(theme, result),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        '模板笔数：${template.strokeCount} · '
                        '形状阈值 ${template.shapeThreshold.toStringAsFixed(4)} · '
                        '行为阈值 ${template.behaviorThreshold.toStringAsFixed(4)}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.white38),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _resultCard(ThemeData theme, AuthResult result) {
    final color = result.accepted ? Colors.greenAccent : Colors.redAccent;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  result.accepted ? Icons.check_circle : Icons.cancel,
                  color: color,
                ),
                const SizedBox(width: 8),
                Text(
                  result.accepted ? '通过' : '拒绝',
                  style: theme.textTheme.titleLarge?.copyWith(color: color),
                ),
                const Spacer(),
                Text(
                  result.reason,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.white54),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _kv(
              '形状',
              '${result.shapeDistance.toStringAsFixed(4)} / '
                  '${result.shapeThreshold.toStringAsFixed(4)}'
                  '（${result.shapeRatio.toStringAsFixed(2)}×）',
            ),
            _kv(
              '行为',
              '${result.behaviorDistance.toStringAsFixed(4)} / '
                  '${result.behaviorThreshold.toStringAsFixed(4)}'
                  '（${result.behaviorRatio.toStringAsFixed(2)}×）',
            ),
            const SizedBox(height: 8),
            Text(
              '判定规则：两项都不超过阈值才通过；任一项超阈值即拒绝。'
              '本次结果已记录，可在首页“模板与验证记录”导出。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.white54),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _verify,
              icon: const Icon(Icons.refresh),
              label: const Text('再测一次'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 64,
              child: Text(k, style: const TextStyle(color: Colors.white54)),
            ),
            Expanded(child: Text(v)),
          ],
        ),
      );

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
