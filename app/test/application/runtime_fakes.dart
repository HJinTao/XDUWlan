import 'dart:async';

import 'package:xduwlan_app/application/app_runtime_controller.dart';
import 'package:xduwlan_app/application/desktop_host.dart';
import 'package:xduwlan_app/application/diagnostics.dart';
import 'package:xduwlan_app/application/recovery_controller.dart';
import 'package:xduwlan_app/application/recovery_service.dart';
import 'package:xduwlan_app/application/settings.dart';
import 'package:xduwlan_app/core/domain.dart';

class RuntimeHarness {
  RuntimeHarness({bool background = false}) {
    recovery = RecoveryController(
      service: RecoveryService(probe: probe, portal: portal, store: accounts),
      store: accounts,
    );
    runtime = AppRuntimeController(
      recovery: recovery,
      desktop: desktop,
      settingsStore: settings,
      diagnosticStore: diagnostics,
      background: background,
    );
  }
  final probe = TestProbe();
  final portal = TestPortal();
  final accounts = TestAccounts();
  final desktop = TestDesktop();
  final settings = TestSettings();
  final diagnostics = TestDiagnostics();
  late final RecoveryController recovery;
  late final AppRuntimeController runtime;
  void dispose() {
    runtime.dispose();
    recovery.dispose();
  }
}

class TestProbe implements NetworkProbe {
  NetworkState state = NetworkState.online;
  Completer<NetworkState>? pending;
  int calls = 0;
  OperationScope? scope;
  @override
  Future<NetworkObservation> check(OperationScope scope) async {
    this.scope = scope;
    calls++;
    final result = pending == null ? state : await pending!.future;
    return NetworkObservation(
      link: result == NetworkState.portalRequired
          ? NetworkLink.wifi
          : NetworkLink.unknown,
      campus: switch (result) {
        NetworkState.portalRequired =>
          CampusNetworkState.authenticationRequired,
        NetworkState.online => CampusNetworkState.online,
        NetworkState.unavailable => CampusNetworkState.unavailable,
        NetworkState.unknown => CampusNetworkState.unknown,
      },
      portal: result,
      authenticationAllowed: result == NetworkState.portalRequired,
    );
  }
}

class TestPortal implements PortalClient {
  FailureCode? failure;
  FailureCode? firstFailure;
  Completer<void>? pendingAuthentication;
  int calls = 0;
  TestProbe? restoreProbe;
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
    await beforeSubmit();
    calls++;
    if (calls == 1 && pendingAuthentication != null) {
      await pendingAuthentication!.future;
    }
    if (calls == 1 && firstFailure != null) throw AppFailure(firstFailure!);
    if (failure != null) throw AppFailure(failure!);
    restoreProbe?.state = NetworkState.online;
  }
}

class TestAccounts implements CredentialStore {
  Credentials? value = const Credentials('test-user', 'test-password');
  int reads = 0;
  @override
  Future<Credentials?> load() async {
    reads++;
    return value;
  }

  @override
  Future<void> save(Credentials credentials) async {
    value = credentials;
  }
}

class TestSettings implements SettingsStore {
  AppSettings value = const AppSettings();
  Completer<AppSettings>? pending;
  bool failLoad = false;
  bool failSave = false;
  Completer<void>? pendingSave;
  @override
  Future<AppSettings> load() async {
    if (failLoad) throw const FormatException();
    return pending == null ? value : await pending!.future;
  }

  @override
  Future<void> save(AppSettings settings) async {
    if (failSave) throw const FormatException();
    if (pendingSave != null) await pendingSave!.future;
    value = settings;
  }
}

class TestDiagnostics implements DiagnosticStore {
  final records = <DiagnosticRecord>[];
  bool fail = false;
  @override
  Future<List<DiagnosticRecord>> load() async => List.of(records);
  @override
  Future<void> append(DiagnosticRecord record) async {
    if (fail) throw const FormatException();
    records.insert(0, record);
  }

  @override
  Future<void> clear() async {
    records.clear();
  }
}

class TestDesktop implements DesktopHost {
  void Function()? onInitialize;
  final started = <String>[];
  final disposed = <String>[];
  final notifications = <OperationReport>[];
  final menu = <TrayState>[];
  final pending = <String, Completer<void>>{};
  final failures = <String>{};
  bool enabled = false;
  bool background = false;
  bool visible = false;
  int shows = 0;
  int hides = 0;
  void Function()? close;
  void Function()? suspend;
  void Function()? resume;
  void Function(TrayAction)? action;
  Future<void> _initialize(String name) async {
    onInitialize?.call();
    started.add(name);
    if (pending[name] != null) await pending[name]!.future;
    if (failures.contains(name)) throw const FormatException();
  }

  @override
  Future<void> initializeWindow({
    required bool background,
    required void Function() onClose,
    required void Function() onSuspend,
    required void Function() onResume,
  }) async {
    this.background = background;
    close = onClose;
    suspend = onSuspend;
    resume = onResume;
    await _initialize('window');
    visible = !background;
  }

  @override
  Future<void> initializeTray(void Function(TrayAction) onAction) async {
    action = onAction;
    await _initialize('tray');
  }

  @override
  Future<void> initializeNotifications() => _initialize('notifications');
  @override
  Future<bool> initializeStartup() async {
    await _initialize('startup');
    return enabled;
  }

  @override
  Future<bool> setLaunchAtStartup(bool value) async {
    if (failures.contains('startupChange')) throw const FormatException();
    enabled = value;
    return enabled;
  }

  @override
  Future<void> updateTray(TrayState state) async {
    menu.add(state);
  }

  @override
  Future<void> showWindow() async {
    shows++;
    visible = true;
  }

  @override
  Future<void> hideWindow() async {
    hides++;
    visible = false;
  }

  @override
  Future<void> notifyAuthentication(OperationReport report) async {
    if (failures.contains('notify')) throw const FormatException();
    notifications.add(report);
  }

  @override
  Future<void> disposeTray() async {
    disposed.add('tray');
  }

  @override
  Future<void> exit() async {
    disposed.add('exit');
  }

  @override
  String? get trayAdvice => null;
}
