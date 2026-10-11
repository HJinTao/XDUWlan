import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:xduwlan_app/application/app_runtime_controller.dart';
import 'package:xduwlan_app/application/desktop_host.dart';
import 'package:xduwlan_app/application/diagnostics.dart';
import 'package:xduwlan_app/application/recovery_controller.dart';
import 'package:xduwlan_app/application/recovery_service.dart';
import 'package:xduwlan_app/application/settings.dart';
import 'package:xduwlan_app/core/presentation.dart';
import 'package:xduwlan_app/platform/application_support.dart';
import 'package:xduwlan_app/platform/credential_store.dart';
import 'package:xduwlan_app/platform/desktop_host.dart';
import 'package:xduwlan_app/platform/http_transport.dart';
import 'package:xduwlan_app/platform/network_probe.dart';
import 'package:xduwlan_app/platform/srun_client.dart';

import 'recovery_validation_support.dart';

/// 手动实网验证入口，默认产品入口和自动测试均不调用。
/// 独立构建：flutter build linux --release -t tool/recovery_validation.dart
/// 运行参数：--scenario=observe --duration-seconds=7200 --directory=/tmp/独立空根目录
/// 其他场景：check、authenticate、manual-during-auto、exit-during-operation。
/// 可选：--background、--without-tray。与产品使用相同实例 ID，须顺序运行。
/// 指定根目录中新建唯一私有会话子目录，设置、日志和命令均保存在其中。
/// SSH 驱动：先私下查找该子目录，再原子发布 command；固定命令见 ValidationFiles。
void main(List<String> args) {
  final counters = ValidationCounters();
  void safeFailure() => stdout.writeln(
    ValidationOutput.encode(ValidationEvent.failed, counters: counters),
  );
  final ValidationOptions? options;
  try {
    options = ValidationOptions.parse(args);
  } catch (_) {
    safeFailure();
    exit(64);
  }
  if (options == null) {
    stdout.writeln(
      ValidationOutput.encode(ValidationEvent.help, counters: counters),
    );
    exit(0);
  }
  if (!Platform.isLinux) {
    safeFailure();
    exit(64);
  }
  final selectedOptions = options;
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (_) => safeFailure();
    PlatformDispatcher.instance.onError = (_, _) {
      safeFailure();
      return true;
    };
    runApp(_ValidationApp(options: selectedOptions, counters: counters));
  }, (_, _) => safeFailure());
}

class _ValidationApp extends StatefulWidget {
  const _ValidationApp({required this.options, required this.counters});
  final ValidationOptions options;
  final ValidationCounters counters;
  @override
  State<_ValidationApp> createState() => _ValidationAppState();
}

class _ValidationAppState extends State<_ValidationApp> {
  _ValidationSession? _session;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_start()));
  }

  Future<void> _start() async {
    try {
      final session = await _ValidationSession.create(
        widget.options,
        widget.counters,
      );
      if (!mounted) return;
      setState(() => _session = session);
      await session.run();
    } catch (_) {
      stdout.writeln(
        ValidationOutput.encode(
          ValidationEvent.failed,
          counters: widget.counters,
        ),
      );
      // 尚未装配运行时时没有网络作用域；运行中的错误由 session 通过生产退出处理。
      if (_session == null) exit(65);
      await _session!.driver.dispatch(ValidationCommand.exit);
    }
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'XDUWlan 开发恢复验证工具',
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      appBar: AppBar(title: const Text('XDUWlan 开发恢复验证工具')),
      body: _session == null
          ? const Center(child: Text('正在准备独立验证目录…'))
          : _ValidationPanel(session: _session!),
    ),
  );
}

class _ValidationPanel extends StatelessWidget {
  const _ValidationPanel({required this.session});
  final _ValidationSession session;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session.runtime,
    builder: (context, _) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('此入口用于手动恢复验证；使用现有产品账号，设置与诊断独立保存。'),
          const Text('不读取或修改登录启动项。请勿与产品实例同时运行。'),
          const SizedBox(height: 20),
          Text(
            session.runtime.recovery.busy
                ? stageMessage(session.runtime.recovery.stage)
                : networkMessage(session.runtime.recovery.network),
          ),
          if (session.runtime.recovery.failure != null)
            Text(failureMessage(session.runtime.recovery.failure!)),
          Text(
            '托盘：${session.runtime.trayReady
                ? session.runtime.trayAvailable
                      ? '可用'
                      : '不可用'
                : '准备中'}',
          ),
          Text(
            '自动恢复：${session.runtime.settings.automaticRecoveryEnabled ? '开启' : '关闭'}',
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final entry in const {
                ValidationCommand.check: '检查',
                ValidationCommand.authenticate: '认证',
                ValidationCommand.hide: '关闭窗口',
                ValidationCommand.show: '显示窗口',
                ValidationCommand.status: '安全状态',
                ValidationCommand.exit: '退出',
              }.entries)
                FilledButton(
                  onPressed: () =>
                      unawaited(session.driver.dispatch(entry.key)),
                  child: Text(entry.value),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ValidationSession {
  _ValidationSession._(
    this.options,
    this.runtime,
    this.files,
    this.log,
    this.driver,
    this.host,
    this.protocolObserver,
  );
  final ValidationOptions options;
  final AppRuntimeController runtime;
  final ValidationFiles files;
  final _SafeLog log;
  final ValidationDriver driver;
  final _ValidationDesktop host;
  final ProtocolObserver? protocolObserver;
  Timer? _poll;
  Timer? _deadline;
  bool _polling = false;

  static Future<_ValidationSession> create(
    ValidationOptions options,
    ValidationCounters counters,
  ) async {
    // 这里只解析目录并检查独立性，不打开产品凭据或设置文件。
    final productDirectory = await resolveApplicationSupportDirectory();
    final files = await ValidationFiles.create(
      options.directory,
      forbiddenDirectory: productDirectory,
    );
    final settings = LocalSettingsStore(directory: files.directory);
    final automatic =
        options.scenario != ValidationScenario.check &&
        options.scenario != ValidationScenario.authenticate &&
        options.scenario != ValidationScenario.protocolObserve;
    await settings.save(AppSettings(automaticRecoveryEnabled: automatic));
    final transport = CountingTransport(IoPortalTransport(), counters);
    final observationSink =
        options.scenario == ValidationScenario.protocolObserve
        ? InMemoryProtocolObservationSink()
        : null;
    // 现有产品路径保持惰性；工具没有读取或修改账号的其他入口。
    final credentials = CountingCredentials(LocalCredentialStore(), counters);
    final recovery = RecoveryController(
      service: RecoveryService(
        probe: CountingProbe(IoNetworkProbe(transport: transport), counters),
        portal: CountingPortal(
          SrunPortalClient(transport: transport),
          counters,
        ),
        store: credentials,
      ),
      store: credentials,
    );
    final host = _ValidationDesktop(withoutTray: options.withoutTray);
    final runtime = AppRuntimeController(
      recovery: recovery,
      desktop: host,
      settingsStore: settings,
      diagnosticStore: LocalDiagnosticStore(directory: files.directory),
      background: options.background,
    );
    final log = _SafeLog(files.reports, counters);
    final driver = ValidationDriver(
      runtime: runtime,
      counters: counters,
      output: log.write,
      windowVisible: windowManager.isVisible,
    );
    final session = _ValidationSession._(
      options,
      runtime,
      files,
      log,
      driver,
      host,
      options.scenario == ValidationScenario.protocolObserve
          ? ProtocolObserver(
              probe: CountingProbe(
                IoNetworkProbe(transport: transport),
                counters,
              ),
              portal: CountingPortal(
                SrunPortalClient(
                  transport: transport,
                  observationSink: observationSink!,
                ),
                counters,
              ),
              store: credentials,
              sink: observationSink,
              thinkPad: Platform.isLinux,
            )
          : null,
    );
    host.beforeExit = session._beforeExit;
    return session;
  }

  Future<void> run() async {
    driver.emit(ValidationEvent.ready);
    _poll = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => unawaited(_takeCommand()),
    );
    // 仅控制工具观测结束，生产调度器的周期和退避保持原值。
    _deadline = Timer(
      options.duration,
      () => unawaited(driver.dispatch(ValidationCommand.exit)),
    );
    if (options.scenario == ValidationScenario.manualDuringAutomatic) {
      await driver.dispatch(ValidationCommand.authenticateWhenBusy);
    } else if (options.scenario == ValidationScenario.exitDuringOperation) {
      await driver.dispatch(ValidationCommand.exitWhenBusy);
    }
    await runtime.initialize();
    if (driver.exiting) return;
    await driver.snapshot();
    switch (options.scenario) {
      case ValidationScenario.check:
        await driver.dispatch(ValidationCommand.check);
        await driver.settled();
        await runtime.flushDiagnostics();
        await driver.dispatch(ValidationCommand.exit);
      case ValidationScenario.authenticate:
        await driver.dispatch(ValidationCommand.authenticate);
        await driver.settled();
        await runtime.flushDiagnostics();
        await driver.dispatch(ValidationCommand.exit);
      case ValidationScenario.manualDuringAutomatic:
        await driver.settled();
        await runtime.flushDiagnostics();
        await driver.dispatch(ValidationCommand.exit);
      case ValidationScenario.observe:
      case ValidationScenario.protocolObserve:
        if (options.scenario == ValidationScenario.protocolObserve) {
          final observer = protocolObserver;
          if (observer == null) throw const ValidationFailure();
          final observation = await observer.observe(
            candidateReader: files.takeCandidate,
          );
          log.write(
            ValidationOutput.encode(
              ValidationEvent.protocolObservation,
              counters: driver.counters,
              observation: observation,
            ),
          );
          await driver.dispatch(ValidationCommand.exit);
        }
      case ValidationScenario.exitDuringOperation:
        break;
    }
  }

  Future<void> _takeCommand() async {
    if (_polling || driver.exiting) return;
    _polling = true;
    try {
      final command = await files.takeCommand();
      if (command != null) await driver.dispatch(command);
    } catch (_) {
      driver.emit(ValidationEvent.commandRejected);
    } finally {
      _polling = false;
    }
  }

  Future<void> _beforeExit() async {
    _poll?.cancel();
    _deadline?.cancel();
    driver.emit(ValidationEvent.summary);
    await log.close();
  }

  void dispose() {
    _poll?.cancel();
    _deadline?.cancel();
    driver.dispose();
    runtime.dispose();
    runtime.recovery.dispose();
  }
}

/// 保留生产窗口、托盘、通知和退出行为，只隔离真实登录启动项。
class _ValidationDesktop extends PluginDesktopHost {
  _ValidationDesktop({required this.withoutTray});
  final bool withoutTray;
  Future<void> Function()? beforeExit;
  @override
  Future<bool> initializeStartup() async => false;
  @override
  Future<bool> setLaunchAtStartup(bool enabled) async => false;
  @override
  Future<void> initializeTray(void Function(TrayAction) onAction) async {
    if (withoutTray) throw const ValidationFailure();
    await super.initializeTray(onAction);
  }

  @override
  Future<void> initializeWindow({
    required bool background,
    required void Function() onClose,
    required void Function() onSuspend,
    required void Function() onResume,
  }) async {
    await super.initializeWindow(
      background: background,
      onClose: onClose,
      onSuspend: onSuspend,
      onResume: onResume,
    );
    await windowManager.setTitle('XDUWlan 开发恢复验证工具');
  }

  @override
  Future<void> exit() async {
    await beforeExit?.call();
    await super.exit();
  }
}

/// stdout 和独立 JSONL 使用同一安全序列化结果；写入失败不回显异常。
class _SafeLog {
  _SafeLog(File file, this.counters) : _sink = file.openWrite() {
    unawaited(_sink.done.then<void>((_) {}, onError: (Object _) => _failed()));
  }
  final IOSink _sink;
  final ValidationCounters counters;
  bool _closed = false;
  bool _failureReported = false;
  void _failed() {
    if (_failureReported) return;
    _failureReported = true;
    stdout.writeln(
      ValidationOutput.encode(ValidationEvent.failed, counters: counters),
    );
  }

  void write(String line) {
    stdout.writeln(line);
    if (!_closed) _sink.writeln(line);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _sink.flush();
      await _sink.close();
    } catch (_) {
      // 诊断文件失败只公开安全失败标志，不阻止生产退出。
      _failed();
    }
  }
}
