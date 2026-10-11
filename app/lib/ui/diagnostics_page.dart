import 'package:flutter/material.dart';

import '../application/app_runtime_controller.dart';
import '../core/domain.dart';
import '../core/presentation.dart';

String formatTime(DateTime? time) {
  if (time == null) return '尚无记录';
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

class DiagnosticsPage extends StatelessWidget {
  const DiagnosticsPage({super.key, required this.runtime});
  final AppRuntimeController runtime;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: runtime,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('诊断记录'),
        actions: [
          TextButton(
            onPressed: runtime.clearDiagnostics,
            child: const Text('清空'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (runtime.diagnosticsError case final message?)
            Padding(padding: const EdgeInsets.all(16), child: Text(message)),
          Expanded(
            child: runtime.records.isEmpty
                ? const Center(child: Text('暂无诊断记录'))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: runtime.records.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, index) {
                      final record = runtime.records[index];
                      final source = switch (record.source) {
                        OperationSource.manual => '手动',
                        OperationSource.automatic => '自动',
                        OperationSource.tray => '托盘',
                        OperationSource.background => '后台',
                      };
                      final action = record.action == OperationKind.check
                          ? '检查'
                          : '认证';
                      final result = record.failure != null
                          ? failureMessage(record.failure!)
                          : record.outcome == RecoveryOutcome.restored
                          ? '认证成功，已恢复联网。'
                          : networkMessage(record.network);
                      return ListTile(
                        title: Text(
                          '$source · $action · ${networkMessage(record.network)}',
                        ),
                        subtitle: Text(
                          '${formatTime(record.time)} · ${record.elapsedMilliseconds} ms\n$result',
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}
