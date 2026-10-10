import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xduwlan_app/application/recovery_controller.dart';
import 'package:xduwlan_app/application/recovery_service.dart';
import 'package:xduwlan_app/core/domain.dart';
import 'package:xduwlan_app/ui/home.dart';

void main() {
  testWidgets('打开主界面不会读取凭据或自行发起网络检查', (tester) async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);
    await _showHome(tester, harness.controller);

    expect(find.text('XDUWlan'), findsOneWidget);
    expect(find.text('西电校园网'), findsOneWidget);
    expect(find.text('网络状态未确认'), findsOneWidget);
    expect(harness.probe.checks, 0);
    expect(harness.store.loads, 0);
  });

  testWidgets('配置使用空白隐藏密码输入并保存用户填写的账号', (tester) async {
    final harness = _Harness();
    harness.store.saved = const Credentials('previous-user', 'previous-secret');
    addTearDown(harness.controller.dispose);
    await _showHome(tester, harness.controller);
    await tester.tap(find.text('配置账号'));
    await tester.pumpAndSettle();

    final passwordField = _field('密码');
    final passwordInput = tester.widget<TextField>(
      find.descendant(of: passwordField, matching: find.byType(TextField)),
    );
    expect(passwordInput.obscureText, isTrue);
    expect(passwordInput.controller!.text, isEmpty);
    expect(harness.store.loads, 0);

    await tester.enterText(_field('账号'), 'demo-user');
    await tester.enterText(passwordField, 'demo-secret');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(harness.store.saved!.username, 'demo-user');
    expect(harness.store.saved!.password, 'demo-secret');
    expect(harness.store.saved!.operatorSuffix, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('已保存'), findsOneWidget);

    await tester.tap(find.text('配置账号'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.descendant(of: _field('密码'), matching: find.byType(TextField)),
          )
          .controller!
          .text,
      isEmpty,
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('空账号和密码阻止保存并给出可操作提示', (tester) async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);
    await _showHome(tester, harness.controller);
    await tester.tap(find.text('配置账号'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('请输入账号'), findsOneWidget);
    expect(find.text('请输入密码'), findsOneWidget);
    expect(harness.store.saves, 0);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('凭据库保存失败保留表单并显示安全建议', (tester) async {
    final harness = _Harness();
    harness.store.saveFailure = const AppFailure(
      FailureCode.credentialStoreUnavailable,
    );
    addTearDown(harness.controller.dispose);
    await _showHome(tester, harness.controller);
    await tester.tap(find.text('配置账号'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('账号'), 'demo-user');
    await tester.enterText(_field('密码'), 'demo-secret');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('安全凭据存储不可用'), findsWidgets);
    expect(find.textContaining('AppFailure'), findsNothing);
    expect(_visibleTextContaining('demo-secret'), findsNothing);
    final passwordInput = tester.widget<TextField>(
      find.descendant(of: _field('密码'), matching: find.byType(TextField)),
    );
    expect(passwordInput.enabled, isNot(false));
    expect(passwordInput.obscureText, isTrue);
    expect(passwordInput.controller!.text, 'demo-secret');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('运营商后缀按用户输入保存而格式错误时保留表单', (tester) async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);
    await _showHome(tester, harness.controller);
    await tester.tap(find.text('配置账号'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('账号'), 'demo-user');
    await tester.enterText(_field('密码'), 'demo-secret');
    await tester.enterText(_field('运营商后缀（可选）'), 'untrusted suffix');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(harness.store.saves, 0);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('格式不正确'), findsWidgets);
    await tester.enterText(_field('运营商后缀（可选）'), '@demo');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(harness.store.saved!.operatorSuffix, '@demo');
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('保存期间禁止重复提交和关闭表单', (tester) async {
    final harness = _Harness();
    final pending = Completer<void>();
    harness.store.pendingSave = pending.future;
    addTearDown(harness.controller.dispose);
    await _showHome(tester, harness.controller);
    await tester.tap(find.text('配置账号'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('账号'), 'demo-user');
    await tester.enterText(_field('密码'), 'demo-secret');
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(tester.widget<FilledButton>(_button('正在保存')).onPressed, isNull);
    expect(tester.widget<TextButton>(_button('取消')).onPressed, isNull);
    expect(
      tester
          .widget<TextField>(
            find.descendant(of: _field('密码'), matching: find.byType(TextField)),
          )
          .enabled,
      isFalse,
    );
    await tester.tap(find.text('正在保存'));
    await tester.pump();
    expect(harness.store.saves, 1);

    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('网络检查期间禁用操作并阻止重复触发', (tester) async {
    final harness = _Harness();
    final pending = Completer<NetworkState>();
    harness.probe.pending = pending.future;
    addTearDown(harness.controller.dispose);
    await _showHome(tester, harness.controller);
    await tester.tap(find.text('检查网络'));
    await tester.pump();

    expect(find.text('正在检查网络'), findsOneWidget);
    expect(tester.widget<FilledButton>(_button('一键认证')).onPressed, isNull);
    expect(tester.widget<TextButton>(_button('检查网络')).onPressed, isNull);
    expect(tester.widget<TextButton>(_button('配置账号')).onPressed, isNull);
    await tester.tap(find.text('一键认证'));
    await tester.tap(find.text('检查网络'));
    await tester.pump();
    expect(harness.probe.checks, 1);
    expect(harness.store.loads, 0);

    pending.complete(NetworkState.online);
    await tester.pumpAndSettle();
    expect(find.text('网络已连接'), findsOneWidget);
  });

  testWidgets('已联网的一键认证显示结果且不访问凭据', (tester) async {
    final harness = _Harness();
    harness.probe.result = NetworkState.online;
    addTearDown(harness.controller.dispose);
    await _showHome(tester, harness.controller);
    await tester.tap(find.text('一键认证'));
    await tester.pumpAndSettle();

    expect(find.text('网络已连接'), findsOneWidget);
    expect(find.textContaining('无需认证'), findsOneWidget);
    expect(harness.store.loads, 0);
    expect(harness.portal.authentications, 0);
  });

  testWidgets('认证拒绝只显示安全的账号检查建议', (tester) async {
    final harness = _Harness();
    harness.probe.result = NetworkState.portalRequired;
    harness.store.saved = const Credentials('demo-user', 'demo-secret');
    harness.portal.failure = const AppFailure(FailureCode.authRejected);
    addTearDown(harness.controller.dispose);
    await _showHome(tester, harness.controller);
    await tester.tap(find.text('一键认证'));
    await tester.pumpAndSettle();

    expect(find.textContaining('核对账号密码'), findsOneWidget);
    expect(find.textContaining('AppFailure'), findsNothing);
    expect(find.textContaining('demo-user'), findsNothing);
    expect(find.textContaining('demo-secret'), findsNothing);
  });

  testWidgets('400 像素窗口和放大文字下主界面与表单无溢出', (tester) async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);
    await tester.binding.setSurfaceSize(const Size(400, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _showHome(tester, harness.controller, textScale: 1.8);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('配置账号'));
    await tester.tap(find.text('配置账号'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('请输入账号'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });
}

Finder _field(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(TextFormField));

Finder _button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
);

Finder _visibleTextContaining(String value) => find.byWidgetPredicate(
  (widget) => switch (widget) {
    Text() => (widget.data ?? widget.textSpan?.toPlainText() ?? '').contains(
      value,
    ),
    RichText() => widget.text.toPlainText().contains(value),
    _ => false,
  },
);

Future<void> _showHome(
  WidgetTester tester,
  RecoveryController controller, {
  double textScale = 1,
}) => tester.pumpWidget(
  MaterialApp(
    theme: ThemeData(useMaterial3: true),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: XduwlanHome(controller: controller),
  ),
);

class _Harness {
  _Harness() {
    controller = RecoveryController(
      service: RecoveryService(probe: probe, portal: portal, store: store),
      store: store,
    );
  }
  final probe = _Probe();
  final portal = _Portal();
  final store = _Store();
  late final RecoveryController controller;
}

class _Probe implements NetworkProbe {
  NetworkState result = NetworkState.unknown;
  Future<NetworkState>? pending;
  int checks = 0;
  @override
  Future<NetworkState> check(OperationScope scope) async {
    checks++;
    return pending == null ? result : await pending!;
  }
}

class _Store implements CredentialStore {
  Credentials? saved;
  AppFailure? saveFailure;
  Future<void>? pendingSave;
  int loads = 0;
  int saves = 0;
  @override
  Future<Credentials?> load() async {
    loads++;
    return saved;
  }

  @override
  Future<void> save(Credentials credentials) async {
    saves++;
    if (saveFailure case final failure?) throw failure;
    if (pendingSave case final pending?) await pending;
    saved = credentials;
  }
}

class _Portal implements PortalClient {
  AppFailure? failure;
  int authentications = 0;
  @override
  Future<PortalContext> prepare(OperationScope scope) async =>
      PortalContext(Uri.parse('https://portal.invalid'), '192.0.2.1', '1');
  @override
  Future<void> authenticate(
    PortalContext context,
    Credentials credentials,
    OperationScope scope, {
    required Future<void> Function() beforeSubmit,
  }) async {
    authentications++;
    if (failure case final error?) throw error;
    await beforeSubmit();
  }
}
