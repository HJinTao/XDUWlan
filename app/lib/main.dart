import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'application/recovery_controller.dart';
import 'application/recovery_service.dart';
import 'platform/credential_store.dart';
import 'platform/http_transport.dart';
import 'platform/network_probe.dart';
import 'platform/srun_client.dart';
import 'ui/home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const XduwlanApp());
}

/// 装配桌面应用，失去活动前台状态时中止网络操作。
class XduwlanApp extends StatefulWidget {
  const XduwlanApp({super.key, this.controller});
  final RecoveryController? controller;

  @override
  State<XduwlanApp> createState() => _XduwlanAppState();
}

class _XduwlanAppState extends State<XduwlanApp> with WidgetsBindingObserver {
  late final RecoveryController _controller;

  @override
  void initState() {
    super.initState();
    final store = LocalCredentialStore();
    final transport = IoPortalTransport();
    _controller =
        widget.controller ??
        RecoveryController(
          service: RecoveryService(
            probe: IoNetworkProbe(transport: transport),
            portal: SrunPortalClient(transport: transport),
            store: store,
          ),
          store: store,
        );
    WidgetsBinding.instance.addObserver(this);
    _controller.setForeground(
      SchedulerBinding.instance.lifecycleState == AppLifecycleState.resumed,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller.setForeground(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'XDUWlan',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3867B0)),
      useMaterial3: true,
    ),
    home: XduwlanHome(controller: _controller),
  );
}
