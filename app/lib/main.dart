import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'application/app_runtime_controller.dart';
import 'application/diagnostics.dart';
import 'application/recovery_controller.dart';
import 'application/recovery_service.dart';
import 'application/settings.dart';
import 'platform/credential_store.dart';
import 'platform/desktop_host.dart';
import 'platform/http_transport.dart';
import 'platform/network_probe.dart';
import 'platform/srun_client.dart';
import 'ui/home.dart';

/// 首帧前仅同步装配对象；所有外部能力在首帧后初始化。
void main(List<String> args) {
  final store = LocalCredentialStore();
  final transport = IoPortalTransport();
  final recovery = RecoveryController(
    service: RecoveryService(
      probe: IoNetworkProbe(transport: transport),
      portal: SrunPortalClient(transport: transport),
      store: store,
    ),
    store: store,
  );
  final runtime = AppRuntimeController(
    recovery: recovery,
    desktop: PluginDesktopHost(),
    settingsStore: LocalSettingsStore(),
    diagnosticStore: LocalDiagnosticStore(),
    background:
        args.contains('--background') ||
        Platform.executableArguments.contains('--background'),
  );
  runApp(XduwlanApp(runtime: runtime, ownsRuntime: true));
}

class XduwlanApp extends StatefulWidget {
  const XduwlanApp({
    super.key,
    required this.runtime,
    this.ownsRuntime = false,
  });
  final AppRuntimeController runtime;
  final bool ownsRuntime;
  @override
  State<XduwlanApp> createState() => _XduwlanAppState();
}

class _XduwlanAppState extends State<XduwlanApp> {
  final _navigator = GlobalKey<NavigatorState>();
  bool _configuring = false;
  @override
  void initState() {
    super.initState();
    widget.runtime.onConfigureRequest = _configure;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.runtime.initialize());
    });
  }

  void _configure() {
    final context = _navigator.currentContext;
    if (context == null || _configuring || !mounted) return;
    _configuring = true;
    unawaited(
      showAccountConfiguration(
        context,
        widget.runtime.recovery,
      ).whenComplete(() => _configuring = false),
    );
  }

  @override
  void dispose() {
    widget.runtime.onConfigureRequest = null;
    if (widget.ownsRuntime) {
      widget.runtime.dispose();
      widget.runtime.recovery.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _navigator,
    title: 'XDUWlan',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3867B0)),
      useMaterial3: true,
    ),
    home: XduwlanHome(
      controller: widget.runtime.recovery,
      runtime: widget.runtime,
    ),
  );
}
