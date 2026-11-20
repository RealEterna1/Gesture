import 'package:flutter/material.dart';

import 'data_screen.dart';
import 'diagnostics_screen.dart';
import 'store.dart';
import 'auth/auth_store.dart';
import 'enroll_screen.dart';
import 'verify_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _subject = TextEditingController(text: 'P01');
  String _gesture = 'G1';
  Map<String, dynamic> _device = {};
  int _templateCount = 0;
  int _logCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final device = await SampleStore.deviceInfo();
      final templates = await AuthTemplateStore.list();
      final logs = await AuthLogStore.count();
      if (!mounted) return;
      setState(() {
        _device = device;
        _templateCount = templates.length;
        _logCount = logs;
      });
    } catch (_) {
      // 设备信息获取失败不阻塞使用
    }
  }

  @override
  void dispose() {
    _subject.dispose();
    super.dispose();
  }

  Future<void> _openEnroll() async {
    final subject = _subject.text.trim();
    if (subject.isEmpty) {
      _toast('请填写被试编号');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EnrollScreen(
          subjectId: subject,
          gestureId: _gesture,
          device: _device,
        ),
      ),
    );
    _load();
  }

  Future<void> _openVerify() async {
    final subject = _subject.text.trim();
    if (subject.isEmpty) {
      _toast('请填写被试编号');
      return;
    }
    final exists = await AuthTemplateStore.exists(subject, _gesture);
    if (!mounted) return;
    if (!exists) {
      _toast('还没有模板，请先点“注册模板”');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VerifyScreen(
          subjectId: subject,
          gestureId: _gesture,
          device: _device,
        ),
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deviceName = [
      _device['manufacturer'],
      _device['model'],
    ].where((e) => e != null && '$e'.isNotEmpty).join(' ');

    return Scaffold(
      appBar: AppBar(title: const Text('手势采集')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text('触摸动力学采集', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              '逐笔记录坐标、时间戳、压力与接触面积',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _subject,
              decoration: const InputDecoration(
                labelText: '被试编号',
                hintText: '例如 P01',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _gesture,
              decoration: const InputDecoration(
                labelText: '手势编号',
                border: OutlineInputBorder(),
              ),
              items: [
                for (var i = 1; i <= 10; i++)
                  DropdownMenuItem(value: 'G$i', child: Text('G$i')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _gesture = v);
              },
            ),
            const SizedBox(height: 20),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.phone_android),
                title: Text(deviceName.isEmpty ? '设备信息获取中…' : deviceName),
                subtitle: Text(
                  [
                    if (_device['android_release'] != null)
                      'Android ${_device['android_release']}',
                    if (_device['sdk_int'] != null) 'API ${_device['sdk_int']}',
                    '$_templateCount 个模板 · $_logCount 条验证记录',
                  ].join(' · '),
                ),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DataScreen()),
                );
                _load();
              },
              icon: const Icon(Icons.folder_shared_outlined),
              label: const Text('数据管理（模板 / 验证记录）'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
              ),
              icon: const Icon(Icons.monitor_heart_outlined),
              label: const Text('设备自检（触摸轴 / 原始压力）'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
            ),
            const SizedBox(height: 20),
            Text('认证演示', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openEnroll,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('注册模板'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openVerify,
                    icon: const Icon(Icons.verified_user_outlined),
                    label: const Text('验证'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              '提示：同一被试、同一手势建议在不同时间多次采集（跨会话），'
              '冒用数据请让未注册者先观察再模仿。',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }
}
