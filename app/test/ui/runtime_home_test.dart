import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xduwlan_app/application/settings.dart';
import 'package:xduwlan_app/main.dart';

import '../application/runtime_fakes.dart';

void main() {
  testWidgets('首帧显示并交互，插件与文件准备中只局部禁用', (tester) async {
    final h = RuntimeHarness();
    addTearDown(h.dispose);
    h.settings.pending = Completer<AppSettings>();
    for (final name in ['tray', 'startup', 'notifications', 'window']) {
      h.desktop.pending[name] = Completer<void>();
    }
    final phases = <SchedulerPhase>[];
    h.desktop.onInitialize = () =>
        phases.add(SchedulerBinding.instance.schedulerPhase);
    await tester.pumpWidget(XduwlanApp(runtime: h.runtime));
    expect(find.text('XDUWlan'), findsOneWidget);
    expect(phases, everyElement(SchedulerPhase.postFrameCallbacks));
    expect(h.probe.calls, 0);
    expect(h.accounts.reads, 0);
    expect(find.textContaining('准备中'), findsWidgets);
    await tester.ensureVisible(find.text('配置账号'));
    await tester.tap(find.text('配置账号'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('保存并测试'), findsNothing);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    h.settings.pending!.complete(
      const AppSettings(automaticRecoveryEnabled: false),
    );
    for (final task in h.desktop.pending.values) {
      task.complete();
    }
    await tester.pumpAndSettle();
  });

  testWidgets('启动项已查询但设置仍准备中时开关局部禁用', (tester) async {
    final h = RuntimeHarness();
    addTearDown(h.dispose);
    h.settings.pending = Completer<AppSettings>();
    await tester.pumpWidget(XduwlanApp(runtime: h.runtime));
    await tester.pumpAndSettle();
    expect(h.runtime.startupReady, isTrue);
    final startup = find.ancestor(
      of: find.text('登录系统后启动'),
      matching: find.byType(SwitchListTile),
    );
    expect(tester.widget<SwitchListTile>(startup).onChanged, isNull);
    expect(find.text('配置账号'), findsOneWidget);
    h.settings.pending!.complete(
      const AppSettings(automaticRecoveryEnabled: false),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(startup).onChanged, isNotNull);
  });

  testWidgets('诊断页显示安全记录并可清空，首页显示最近时间', (tester) async {
    final h = RuntimeHarness();
    addTearDown(h.dispose);
    h.settings.value = const AppSettings(automaticRecoveryEnabled: false);
    await tester.pumpWidget(XduwlanApp(runtime: h.runtime));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('检查网络'));
    await tester.tap(find.text('检查网络'));
    await tester.pumpAndSettle();
    expect(find.textContaining('最近检查：'), findsOneWidget);
    await tester.ensureVisible(find.text('诊断记录'));
    await tester.tap(find.text('诊断记录'));
    await tester.pumpAndSettle();
    expect(find.textContaining('手动 · 检查'), findsOneWidget);
    expect(find.textContaining('test-user'), findsNothing);
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    expect(find.text('暂无诊断记录'), findsOneWidget);
  });
}
