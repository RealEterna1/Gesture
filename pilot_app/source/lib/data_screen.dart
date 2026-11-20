import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'auth/auth_core.dart';
import 'auth/auth_store.dart';
import 'condition_labels.dart';

/// 数据管理：模板与验证记录合并在一个页面，统一导出/清空。
class DataScreen extends StatefulWidget {
  const DataScreen({super.key});

  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<AuthTemplate> _templates = [];
  List<VerificationRecord> _logs = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final templates = await AuthTemplateStore.list();
    final logs = await AuthLogStore.list();
    logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (!mounted) return;
    setState(() {
      _templates = templates;
      _logs = logs;
      _loading = false;
    });
  }

  Future<File> _buildBundle() async {
    final document = <String, dynamic>{
      'exported_at': DateTime.now().toIso8601String(),
      'template_count': _templates.length,
      'templates': _templates.map((t) => t.toJson()).toList(),
      'verification_count': _logs.length,
      'verification_logs': _logs.map((r) => r.toJson()).toList(),
    };
    final root = await getApplicationDocumentsDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-');
    final file = File('${root.path}/gesture_export_$stamp.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(document),
    );
    return file;
  }

  Future<void> _exportAll() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await _buildBundle();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: '全部数据（模板 ${_templates.length}、'
              '验证记录 ${_logs.length}）',
        ),
      );
    } catch (e) {
      _toast('导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空全部数据？'),
        content: Text(
          '将删除：\n'
          '模板 ${_templates.length} 个\n'
          '验证记录 ${_logs.length} 条\n\n'
          '删除后无法恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('全部清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AuthTemplateStore.deleteAll();
    await AuthLogStore.clear();
    _toast('已清空模板和验证记录');
    _load();
  }

  Future<void> _deleteTemplate(AuthTemplate template) async {
    await AuthTemplateStore.delete(template.subjectId, template.gestureId);
    _load();
  }

  Future<void> _deleteLog(VerificationRecord record) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条验证记录？'),
        content: Text(
          '${record.timestamp}\n'
          '${record.subjectId} · ${record.gestureId} · '
          '${record.accepted ? '通过' : '拒绝'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AuthLogStore.delete(record);
    _toast('已删除该条记录');
    _load();
  }

  Future<void> _editThresholds(AuthTemplate template) async {
    final shape = TextEditingController(
      text: template.shapeThreshold.toStringAsFixed(4),
    );
    final behavior = TextEditingController(
      text: template.behaviorThreshold.toStringAsFixed(4),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改阈值'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: shape,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '形状阈值',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: behavior,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '行为阈值',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '阈值越小越严格。建议用 pilot 数据算出的 EER/FAR 结果来填。',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final shapeValue = double.tryParse(shape.text.trim());
    final behaviorValue = double.tryParse(behavior.text.trim());
    if (shapeValue == null ||
        behaviorValue == null ||
        shapeValue <= 0 ||
        behaviorValue <= 0) {
      _toast('阈值必须是大于 0 的数字');
      return;
    }
    await AuthTemplateStore.save(
      template.copyWith(
        shapeThreshold: shapeValue,
        behaviorThreshold: behaviorValue,
      ),
    );
    _load();
  }

  Widget _templatesTab(ThemeData theme) {
    if (_templates.isEmpty) {
      return const Center(
        child: Text(
          '还没有模板\n回首页点“注册模板”',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _templates.length,
      itemBuilder: (context, i) {
        final template = _templates[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text('${template.subjectId} · ${template.gestureId}'),
            subtitle: Text(
              '${template.strokeCount} 笔 · '
              '形状 ${template.shapeThreshold.toStringAsFixed(4)} · '
              '行为 ${template.behaviorThreshold.toStringAsFixed(4)}\n'
              '${template.createdAt}',
              style: const TextStyle(fontSize: 12),
            ),
            isThreeLine: true,
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') {
                  _editThresholds(template);
                } else if (value == 'delete') {
                  _deleteTemplate(template);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('修改阈值')),
                PopupMenuItem(value: 'delete', child: Text('删除模板')),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _logsTab(ThemeData theme) {
    if (_logs.isEmpty) {
      return const Center(
        child: Text(
          '还没有验证记录\n去“验证”一次就会自动记录',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _logs.length,
      itemBuilder: (context, i) {
        final record = _logs[i];
        final condition =
            kConditionLabels[record.condition] ?? record.condition;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(
              record.accepted ? Icons.check_circle : Icons.cancel,
              color:
                  record.accepted ? Colors.greenAccent : Colors.redAccent,
            ),
            title: Text(
              '${record.subjectId} · ${record.gestureId} · '
              '${record.accepted ? '通过' : '拒绝'}',
            ),
            subtitle: Text(
              '$condition'
              '${record.performerId.isEmpty ? '' : ' · 执行者 ${record.performerId}'}\n'
              '形状 ${record.shapeRatio.toStringAsFixed(2)}× · '
              '行为 ${record.behaviorRatio.toStringAsFixed(2)}× · '
              '${record.reason}',
              style: const TextStyle(fontSize: 12),
            ),
            isThreeLine: true,
            trailing: IconButton(
              onPressed: () => _deleteLog(record),
              icon: const Icon(Icons.delete_outline),
            ),
          ),
        );
      },
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据管理'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _exportAll,
            icon: const Icon(Icons.ios_share),
            tooltip: '导出全部',
          ),
          IconButton(
            onPressed: _clearAll,
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: '清空全部',
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: '模板 ${_templates.length}'),
            Tab(text: '验证记录 ${_logs.length}'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _templatesTab(theme),
                _logsTab(theme),
              ],
            ),
    );
  }
}
