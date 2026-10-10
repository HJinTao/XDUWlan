import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xduwlan_app/application/app_runtime_controller.dart';
import 'package:xduwlan_app/application/diagnostics.dart';
import 'package:xduwlan_app/core/domain.dart';

enum ValidationScenario {
  check,
  authenticate,
  observe,
  manualDuringAutomatic,
  exitDuringOperation,
}

enum ValidationCommand {
  check,
  authenticate,
  hide,
  show,
  status,
  automaticOn,
  automaticOff,
  authenticateWhenBusy,
  exitWhenBusy,
  exit,
}

enum ValidationEvent {
  help,
  ready,
  report,
  phase,
  status,
  summary,
  commandAccepted,
  commandRejected,
  exiting,
  failed,
}

/// 不携带输入、文件路径或底层异常。
class ValidationFailure implements Exception {
  const ValidationFailure();
}

class ValidationOptions {
  const ValidationOptions({
    required this.scenario,
    required this.duration,
    this.directory,
    this.background = false,
    this.withoutTray = false,
  });
  final ValidationScenario scenario;
  final Duration duration;
  final String? directory;
  final bool background;
  final bool withoutTray;
  static const _scenarios = {
    'check': ValidationScenario.check,
    'authenticate': ValidationScenario.authenticate,
    'observe': ValidationScenario.observe,
    'manual-during-auto': ValidationScenario.manualDuringAutomatic,
    'exit-during-operation': ValidationScenario.exitDuringOperation,
  };

  /// 没有显式场景时不创建运行时；错误永不回显命令行输入。
  static ValidationOptions? parse(List<String> args) {
    if (args.isEmpty || (args.length == 1 && args.single == '--help')) {
      return null;
    }
    final values = <String, String>{};
    for (final argument in args) {
      final separator = argument.indexOf('=');
      final key = separator < 0 ? argument : argument.substring(0, separator);
      final value = separator < 0 ? '' : argument.substring(separator + 1);
      if (!{
            '--scenario',
            '--directory',
            '--duration-seconds',
            '--background',
            '--without-tray',
          }.contains(key) ||
          values.containsKey(key) ||
          (key == '--background' || key == '--without-tray') &&
              separator >= 0) {
        throw const FormatException('验证参数不可用');
      }
      values[key] = value;
    }
    final scenario = _scenarios[values['--scenario']];
    final secondsText = values['--duration-seconds'] ?? '7200';
    final seconds = int.tryParse(secondsText);
    final directory = values['--directory'];
    if (scenario == null ||
        !RegExp(r'^[0-9]{1,5}$').hasMatch(secondsText) ||
        seconds == null ||
        seconds < 1 ||
        seconds > 10800 ||
        directory != null &&
            (!directory.startsWith('/') ||
                directory.contains(RegExp(r'[\x00-\x1f\x7f]')))) {
      throw const FormatException('验证参数不可用');
    }
    return ValidationOptions(
      scenario: scenario,
      duration: Duration(seconds: seconds),
      directory: directory,
      background: values.containsKey('--background'),
      withoutTray: values.containsKey('--without-tray'),
    );
  }
}

class ValidationFiles {
  ValidationFiles._(this.directory);
  final Directory directory;
  File get command => File('${directory.path}/command');
  File get reports => File('${directory.path}/reports.jsonl');

  /// 只使用全新的空目录，拒绝产品目录、其子目录及符号链接别名。
  static Future<ValidationFiles> create(
    String? path, {
    Directory? forbiddenDirectory,
  }) async {
    try {
      final directory = path == null
          ? await Directory.systemTemp.createTemp(
              'xduwlan-recovery-validation-',
            )
          : Directory(path);
      final type = await FileSystemEntity.type(
        directory.path,
        followLinks: false,
      );
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.directory) {
        throw const ValidationFailure();
      }
      if (forbiddenDirectory != null) {
        final selected = await _canonical(directory);
        final forbidden = await _canonical(forbiddenDirectory);
        if (selected == forbidden || selected.startsWith('$forbidden/')) {
          throw const ValidationFailure();
        }
      }
      if (type == FileSystemEntityType.directory &&
          !await directory.list().isEmpty) {
        throw const ValidationFailure();
      }
      await directory.create(recursive: true);
      return ValidationFiles._(directory);
    } catch (_) {
      throw const ValidationFailure();
    }
  }

  static Future<String> _canonical(Directory directory) async {
    final absolute = Directory.fromUri(directory.absolute.uri.normalizePath());
    if (await absolute.exists()) return absolute.resolveSymbolicLinks();
    final parent = await _canonical(absolute.parent);
    return '$parent/${absolute.uri.pathSegments.where((s) => s.isNotEmpty).last}';
  }

  static const _commands = {
    'check': ValidationCommand.check,
    'authenticate': ValidationCommand.authenticate,
    'hide': ValidationCommand.hide,
    'show': ValidationCommand.show,
    'status': ValidationCommand.status,
    'automatic-on': ValidationCommand.automaticOn,
    'automatic-off': ValidationCommand.automaticOff,
    'authenticate-when-busy': ValidationCommand.authenticateWhenBusy,
    'exit-when-busy': ValidationCommand.exitWhenBusy,
    'exit': ValidationCommand.exit,
  };

  /// 每次消费一个命令。输入长度有界，未知内容不输出且不执行。
  Future<ValidationCommand?> takeCommand() async {
    final type = await FileSystemEntity.type(command.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    try {
      if (type != FileSystemEntityType.file) throw const ValidationFailure();
      final input = await command.open();
      final List<int> bytes;
      try {
        bytes = await input.read(129);
      } finally {
        await input.close();
      }
      if (bytes.length > 128) throw const ValidationFailure();
      var text = utf8.decode(bytes);
      if (text.endsWith('\n')) text = text.substring(0, text.length - 1);
      final result = _commands[text];
      if (result == null) throw const ValidationFailure();
      return result;
    } catch (_) {
      throw const ValidationFailure();
    } finally {
      // 只删除独立目录里的命令入口；符号链接不会删除其目标。
      if (type == FileSystemEntityType.file ||
          type == FileSystemEntityType.link) {
        await command.delete();
      }
    }
  }
}

/// 只保留次数，不保留请求参数、响应或凭据。
class ValidationCounters {
  int probes = 0;
  int preparations = 0;
  int authentications = 0;
  int authenticationSubmissions = 0;
  int credentialReads = 0;
  int requests = 0;
  int activeRequests = 0;
  int maxActiveRequests = 0;
  int reports = 0;
  int commands = 0;
  Map<String, int> toJson() => {
    'probes': probes,
    'preparations': preparations,
    'authentications': authentications,
    'authenticationSubmissions': authenticationSubmissions,
    'credentialReads': credentialReads,
    'requests': requests,
    'activeRequests': activeRequests,
    'maxActiveRequests': maxActiveRequests,
    'reports': reports,
    'commands': commands,
  };
}

class ValidationOutput {
  static String encode(
    ValidationEvent event, {
    OperationReport? report,
    required ValidationCounters counters,
    RecoveryStage? phase,
    bool? windowVisible,
    bool? trayAvailable,
  }) => jsonEncode({
    'identity': 'xduwlan-recovery-validation',
    'event': event.name,
    if (report != null) 'report': DiagnosticRecord.fromReport(report).toJson(),
    'counts': counters.toJson(),
    if (phase != null) 'phase': phase.name,
    'windowVisible': ?windowVisible,
    'trayAvailable': ?trayAvailable,
  });
}

class CountingTransport implements PortalTransport {
  CountingTransport(this.inner, this.counters);
  final PortalTransport inner;
  final ValidationCounters counters;
  @override
  Future<PortalResponse> request(
    String method,
    Uri url,
    OperationScope scope,
  ) async {
    counters.requests++;
    counters.activeRequests++;
    if (counters.activeRequests > counters.maxActiveRequests) {
      counters.maxActiveRequests = counters.activeRequests;
    }
    try {
      return await inner.request(method, url, scope);
    } finally {
      counters.activeRequests--;
    }
  }
}

class CountingProbe implements NetworkProbe {
  CountingProbe(this.inner, this.counters);
  final NetworkProbe inner;
  final ValidationCounters counters;
  @override
  Future<NetworkState> check(OperationScope scope) {
    counters.probes++;
    return inner.check(scope);
  }
}

class CountingPortal implements PortalClient {
  CountingPortal(this.inner, this.counters);
  final PortalClient inner;
  final ValidationCounters counters;
  @override
  Future<PortalContext> prepare(OperationScope scope) {
    counters.preparations++;
    return inner.prepare(scope);
  }

  @override
  Future<void> authenticate(
    PortalContext context,
    Credentials credentials,
    OperationScope scope, {
    required Future<void> Function() beforeSubmit,
  }) {
    counters.authentications++;
    return inner.authenticate(
      context,
      credentials,
      scope,
      beforeSubmit: () async {
        await beforeSubmit();
        counters.authenticationSubmissions++;
      },
    );
  }
}

class CountingCredentials implements CredentialStore {
  CountingCredentials(this.inner, this.counters);
  final CredentialStore inner;
  final ValidationCounters counters;
  @override
  Future<Credentials?> load() {
    counters.credentialReads++;
    return inner.load();
  }

  @override
  Future<void> save(Credentials credentials) async {
    throw const AppFailure(FailureCode.credentialStoreUnavailable);
  }
}

/// 命令只调用生产运行时，不建立额外网络调度或绕过串行门闩。
class ValidationDriver {
  ValidationDriver({
    required this.runtime,
    required this.counters,
    required this.output,
    required this.windowVisible,
  }) {
    runtime.recovery.addListener(_changed);
  }
  final AppRuntimeController runtime;
  final ValidationCounters counters;
  final void Function(String) output;
  final Future<bool> Function() windowVisible;
  final Set<Future<void>> _work = {};
  ValidationCommand? _armed;
  OperationReport? _seenReport;
  RecoveryStage? _seenStage;
  int _seenSequence = 0;
  bool? _visible;
  bool exiting = false;
  bool _disposed = false;
  void emit(ValidationEvent event, {OperationReport? report}) {
    if (_disposed) return;
    output(
      ValidationOutput.encode(
        event,
        counters: counters,
        report: report,
        phase: runtime.recovery.stage,
        windowVisible: _visible,
        trayAvailable: runtime.trayReady ? runtime.trayAvailable : null,
      ),
    );
  }

  void _track(Future<dynamic> future) {
    late final Future<void> work;
    work = future
        .then<void>(
          (_) {},
          onError: (Object _) {
            emit(ValidationEvent.failed);
          },
        )
        .whenComplete(() => _work.remove(work));
    _work.add(work);
  }

  void _changed() {
    final recovery = runtime.recovery;
    final report = recovery.lastReport;
    if (report != null && !identical(report, _seenReport)) {
      _seenReport = report;
      counters.reports++;
      emit(ValidationEvent.report, report: report);
    }
    if (recovery.operationSequence != _seenSequence ||
        recovery.stage != _seenStage) {
      _seenSequence = recovery.operationSequence;
      _seenStage = recovery.stage;
      emit(ValidationEvent.phase);
    }
    _dispatchArmed();
  }

  void _dispatchArmed() {
    if (_armed == null || !runtime.recovery.busy || exiting) return;
    final command = _armed!;
    _armed = null;
    // 延后到当前监听回调之后，但仍在同一生产操作期间提交请求。
    _track(Future<void>.microtask(() => dispatch(command)));
  }

  Future<void> dispatch(ValidationCommand command) async {
    if (_disposed || exiting) return;
    counters.commands++;
    emit(ValidationEvent.commandAccepted);
    switch (command) {
      case ValidationCommand.check:
        _track(runtime.check(OperationSource.manual));
      case ValidationCommand.authenticate:
        _track(runtime.authenticate(OperationSource.manual));
      case ValidationCommand.authenticateWhenBusy:
        _armed = ValidationCommand.authenticate;
        _dispatchArmed();
      case ValidationCommand.exitWhenBusy:
        _armed = ValidationCommand.exit;
        _dispatchArmed();
      case ValidationCommand.hide:
        await runtime.closeWindow();
        if (!runtime.trayAvailable) exiting = true;
        await snapshot();
      case ValidationCommand.show:
        await runtime.showWindow();
        await snapshot();
      case ValidationCommand.status:
        await snapshot();
      case ValidationCommand.automaticOn:
        await runtime.setAutomaticRecovery(true);
      case ValidationCommand.automaticOff:
        await runtime.setAutomaticRecovery(false);
      case ValidationCommand.exit:
        exiting = true;
        emit(ValidationEvent.exiting);
        await runtime.exit();
    }
  }

  Future<void> snapshot() async {
    try {
      _visible = await windowVisible();
    } catch (_) {
      _visible = null;
    }
    emit(ValidationEvent.status);
  }

  Future<void> settled() async {
    while (_work.isNotEmpty) {
      await Future.wait(List.of(_work));
    }
  }

  void dispose() {
    _disposed = true;
    runtime.recovery.removeListener(_changed);
  }
}
