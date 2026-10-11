import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'application/app_runtime_controller.dart';
import 'application/background_tasks.dart';
import 'application/diagnostics.dart';
import 'application/recovery_controller.dart';
import 'application/recovery_service.dart';
import 'application/settings.dart';
import 'core/domain.dart';
import 'platform/credential_store.dart';
import 'platform/desktop_host.dart';
import 'platform/http_transport.dart';
import 'platform/mobile_host.dart';
import 'platform/network_probe.dart';
import 'platform/ios_network_path.dart';
import 'platform/srun_client.dart';
import 'ui/home.dart';

/// 首帧前仅同步装配对象；所有外部能力在首帧后初始化。
void main(List<String> args) {
  final store = LocalCredentialStore();
  final transport = IoPortalTransport();
  final pathSource = Platform.isIOS ? MethodChannelNetworkPathSource() : null;
  final recovery = RecoveryController(
    service: RecoveryService(
      probe: IoNetworkProbe(transport: transport, pathSource: pathSource),
      portal: SrunPortalClient(transport: transport),
      store: store,
    ),
    store: store,
  );
  final mobile = Platform.isIOS || Platform.isAndroid;
  final runtime = AppRuntimeController(
    recovery: recovery,
    desktop: mobile ? null : PluginDesktopHost(),
    host: mobile ? MobileHost() : null,
    settingsStore: LocalSettingsStore(),
    diagnosticStore: LocalDiagnosticStore(),
    backgroundScheduler: mobile ? WorkmanagerBackgroundTaskScheduler() : null,
    background:
        args.contains('--background') ||
        Platform.executableArguments.contains('--background'),
  );
  runApp(
    XduwlanApp(runtime: runtime, ownsRuntime: true, pathSource: pathSource),
  );
}

class XduwlanApp extends StatefulWidget {
  const XduwlanApp({
    super.key,
    required this.runtime,
    this.ownsRuntime = false,
    this.pathSource,
  });
  final AppRuntimeController runtime;
  final bool ownsRuntime;
  final NetworkPathSource? pathSource;
  @override
  State<XduwlanApp> createState() => _XduwlanAppState();
}

class _XduwlanAppState extends State<XduwlanApp> with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  bool _configuring = false;
  StreamSubscription<NetworkPathSnapshot>? _pathSubscription;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.runtime.onConfigureRequest = _configure;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pathSubscription = widget.pathSource?.pathUpdates.listen((_) {
        if (mounted && widget.runtime.initialized) {
          unawaited(widget.runtime.check(OperationSource.automatic));
        }
      });
      if (mounted) unawaited(widget.runtime.initialize());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.runtime.isDesktop) return;
    switch (state) {
      case AppLifecycleState.resumed:
        widget.runtime.resume();
      case AppLifecycleState.inactive ||
          AppLifecycleState.hidden ||
          AppLifecycleState.paused:
        widget.runtime.suspend();
      case AppLifecycleState.detached:
        break;
    }
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
    WidgetsBinding.instance.removeObserver(this);
    widget.runtime.onConfigureRequest = null;
    _pathSubscription?.cancel();
    if (widget.pathSource is MethodChannelNetworkPathSource) {
      (widget.pathSource! as MethodChannelNetworkPathSource).dispose();
    }
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
