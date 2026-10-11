import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:xduwlan_app/application/app_runtime_controller.dart';
import 'package:xduwlan_app/application/diagnostics.dart';
import 'package:xduwlan_app/core/domain.dart';
import 'package:xduwlan_app/core/srun_protocol.dart';

enum ValidationScenario {
  check,
  authenticate,
  observe,
  protocolObserve,
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
  protocolObservation,
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
    'protocol-observe': ValidationScenario.protocolObserve,
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

enum ProtocolVerificationState { notAttempted, loginSucceeded, verified }

enum ProtocolObservationFailure {
  none,
  unsupportedHost,
  candidateUnavailable,
  candidateInvalid,
  portalUnavailable,
  loginFailed,
  verificationFailed,
  unexpected,
}

class ProtocolObservation {
  const ProtocolObservation({
    required this.candidateAccepted,
    required this.encodingRulePassed,
    required this.verificationState,
    required this.requests,
    required this.submissions,
    required this.credentialReads,
    required this.elapsedMilliseconds,
    required this.failure,
    this.candidateIdentity,
    this.runIdentity,
  });
  final bool candidateAccepted;
  final bool encodingRulePassed;
  final ProtocolVerificationState verificationState;
  final int requests;
  final int submissions;
  final int credentialReads;
  final int elapsedMilliseconds;
  final ProtocolObservationFailure failure;

  /// 仅供同一候选的离线提升门比较，永不序列化。
  final String? candidateIdentity;

  /// 每次观察生成的内部运行标识，永不序列化。
  final String? runIdentity;
  Map<String, Object> toJson() => {
    'candidateAccepted': candidateAccepted,
    'encodingRulePassed': encodingRulePassed,
    'verificationState': verificationState.name,
    'requests': requests,
    'submissions': submissions,
    'credentialReads': credentialReads,
    'elapsedMilliseconds': elapsedMilliseconds,
    'failure': failure.name,
  };
  @override
  String toString() => 'ProtocolObservation(${toJson()})';
}

abstract interface class ProtocolObservationSink
    implements SrunObservationSink {
  bool get encodingRulePassed;
  int get requests;
  int get submissions;
  @override
  void request();
  @override
  void submission();
  @override
  void inspectLoginRequest(
    Map<String, Object> params,
    Credentials credentials,
    PortalContext context,
  );
}

class InMemoryProtocolObservationSink implements ProtocolObservationSink {
  bool _encodingRulePassed = false;
  int _requests = 0;
  int _submissions = 0;
  @override
  bool get encodingRulePassed => _encodingRulePassed;
  @override
  int get requests => _requests;
  @override
  int get submissions => _submissions;
  void reset() {
    _encodingRulePassed = false;
    _requests = 0;
    _submissions = 0;
  }

  @override
  void request() => _requests++;
  @override
  void submission() => _submissions++;
  @override
  void inspectLoginRequest(
    Map<String, Object> params,
    Credentials credentials,
    PortalContext context,
  ) {
    final username = params['username'];
    final info = params['info'];
    final checksum = params['chksum'];
    final password = params['password'];
    _encodingRulePassed =
        username == credentials.username &&
        info is String &&
        checksum is String &&
        password is String &&
        password.startsWith('{MD5}') &&
        password != credentials.password &&
        params['ip'] == context.ip &&
        params['ac_id'] == context.acid;
  }

  @override
  String toString() =>
      'InMemoryProtocolObservationSink(encodingRulePassed=$_encodingRulePassed, requests=$_requests, submissions=$_submissions)';
}

class ProtocolObserver {
  ProtocolObserver({
    required this.probe,
    required this.portal,
    required this.store,
    required this.sink,
    required this.thinkPad,
  });
  final NetworkProbe probe;
  final PortalClient portal;
  final CredentialStore store;
  final ProtocolObservationSink sink;
  final bool thinkPad;

  Future<ProtocolObservation> observe({
    required Future<String?> Function() candidateReader,
  }) async {
    if (sink case final InMemoryProtocolObservationSink memory) {
      memory.reset();
    }
    final started = DateTime.now();
    final runIdentity = _nextProtocolRunIdentity();
    String? candidateIdentity;
    var credentialReads = 0;
    try {
      if (!thinkPad) {
        return _result(
          started,
          credentialReads,
          ProtocolObservationFailure.unsupportedHost,
        );
      }
      final candidate = await candidateReader();
      if (candidate == null || candidate.isEmpty) {
        return _result(
          started,
          credentialReads,
          ProtocolObservationFailure.candidateUnavailable,
        );
      }
      if (!RegExp(r'^@[A-Za-z0-9._-]{1,32}$').hasMatch(candidate)) {
        return _result(
          started,
          credentialReads,
          ProtocolObservationFailure.candidateInvalid,
        );
      }
      candidateIdentity = _candidateIdentity(candidate);
      final scope = OperationScope();
      try {
        if (_portalState(await probe.check(scope)) !=
            NetworkState.portalRequired) {
          return _result(
            started,
            credentialReads,
            ProtocolObservationFailure.portalUnavailable,
          );
        }
        final context = await portal.prepare(scope);
        final loaded = await store.load();
        credentialReads++;
        if (loaded == null) {
          return _result(
            started,
            credentialReads,
            ProtocolObservationFailure.candidateUnavailable,
          );
        }
        final effective = Credentials(
          appendOperatorSuffixOnce(loaded.username.trim(), candidate),
          loaded.password,
        );
        await portal.authenticate(
          context,
          effective,
          scope,
          beforeSubmit: () async {},
        );
        final loginSucceeded = sink.submissions == 1;
        final verified =
            _portalState(await probe.check(scope)) == NetworkState.online;
        return _result(
          started,
          credentialReads,
          verified
              ? ProtocolObservationFailure.none
              : ProtocolObservationFailure.verificationFailed,
          state: verified
              ? ProtocolVerificationState.verified
              : loginSucceeded
              ? ProtocolVerificationState.loginSucceeded
              : ProtocolVerificationState.notAttempted,
          accepted: verified && loginSucceeded && sink.encodingRulePassed,
          candidateIdentity: candidateIdentity,
          runIdentity: runIdentity,
        );
      } finally {
        scope.finish();
      }
    } on AppFailure catch (_) {
      return _result(
        started,
        credentialReads,
        ProtocolObservationFailure.loginFailed,
        candidateIdentity: candidateIdentity,
        runIdentity: runIdentity,
      );
    } catch (_) {
      return _result(
        started,
        credentialReads,
        ProtocolObservationFailure.unexpected,
        candidateIdentity: candidateIdentity,
        runIdentity: runIdentity,
      );
    }
  }

  ProtocolObservation _result(
    DateTime started,
    int credentialReads,
    ProtocolObservationFailure failure, {
    ProtocolVerificationState state = ProtocolVerificationState.notAttempted,
    bool accepted = false,
    String? candidateIdentity,
    String? runIdentity,
  }) => ProtocolObservation(
    candidateAccepted: accepted,
    encodingRulePassed: sink.encodingRulePassed,
    verificationState: state,
    requests: sink.requests,
    submissions: sink.submissions,
    credentialReads: credentialReads,
    elapsedMilliseconds: DateTime.now().difference(started).inMilliseconds,
    failure: failure,
    candidateIdentity: candidateIdentity,
    runIdentity: runIdentity,
  );

  NetworkState _portalState(Object value) => value is NetworkObservation
      ? value.portal
      : value is NetworkState
      ? value
      : NetworkState.unknown;
}

int _protocolRunSequence = 0;

String _nextProtocolRunIdentity() =>
    '${DateTime.now().microsecondsSinceEpoch}-${++_protocolRunSequence}';

String _candidateIdentity(String candidate) =>
    sha256.convert(utf8.encode(candidate)).toString();

/// 由固定的无线 down/up 完成顺序产生的内部证据；不能用布尔值替代。
class ProtocolResetEvidence {
  const ProtocolResetEvidence._(this.identity);
  final String identity;
}

class ProtocolResetEvidenceBuilder {
  bool _downCompleted = false;
  int _sequence = 0;

  void recordDownCompleted() => _downCompleted = true;

  ProtocolResetEvidence? recordUpCompleted() {
    if (!_downCompleted) return null;
    _downCompleted = false;
    return ProtocolResetEvidence._(
      'reset-${DateTime.now().microsecondsSinceEpoch}-${++_sequence}',
    );
  }
}

class ProtocolPromotionGate {
  String? _candidateIdentity;
  final Set<String> _runs = {};
  bool _resetAccepted = false;
  bool get promotable => _runs.length >= 2 && _resetAccepted;
  void record(
    ProtocolObservation observation, {
    ProtocolResetEvidence? resetEvidence,
  }) {
    if (!observation.candidateAccepted ||
        !observation.encodingRulePassed ||
        observation.verificationState != ProtocolVerificationState.verified ||
        observation.failure != ProtocolObservationFailure.none ||
        observation.candidateIdentity == null ||
        observation.runIdentity == null) {
      return;
    }
    final candidate = observation.candidateIdentity!;
    final run = observation.runIdentity!;
    if (_candidateIdentity != null && _candidateIdentity != candidate) return;
    if (!_runs.add(run)) return;
    _candidateIdentity = candidate;
    _resetAccepted = _resetAccepted || resetEvidence != null;
  }
}

class ValidationFiles {
  ValidationFiles._(this.directory);
  final Directory directory;
  File get command => File('${directory.path}/command');
  File get reports => File('${directory.path}/reports.jsonl');
  File get candidate => File('${directory.path}/candidate');

  Future<String?> takeCandidate() async {
    final type = await FileSystemEntity.type(
      candidate.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.file) throw const ValidationFailure();
    final capturedDirectory = await directory.createTemp('.xduwlan-candidate-');
    final captured = File('${capturedDirectory.path}/candidate');
    try {
      await candidate.rename(captured.path);
      final bytes = await captured.readAsBytes();
      if (bytes.length > 128) throw const ValidationFailure();
      final value = utf8.decode(bytes);
      if (value.contains('\n') || value.contains('\r')) {
        throw const ValidationFailure();
      }
      return value;
    } on FormatException {
      throw const ValidationFailure();
    } finally {
      try {
        if (await captured.exists()) await captured.delete();
        await capturedDirectory.delete();
      } catch (_) {
        throw const ValidationFailure();
      }
    }
  }

  /// 只使用新建私有会话目录；指定根目录须为空且不指向产品支持目录。
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
      // 指定根目录只承载新会话，检查后新出现的未知文件不参与任何写入。
      final session = path == null
          ? directory
          : await directory.createTemp('xduwlan-recovery-validation-');
      return ValidationFiles._(session);
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
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.link) {
      throw const ValidationFailure();
    }
    final capturedDirectory = await directory.createTemp('.xduwlan-command-');
    final captured = File('${capturedDirectory.path}/command');
    try {
      // 原子捕获后，新发布的 command 留给下一轮；只处理私有目录里的这一项。
      try {
        await command.rename(captured.path);
      } on PathNotFoundException {
        return null;
      }
      if (await FileSystemEntity.type(captured.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const ValidationFailure();
      }
      final input = await captured.open();
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
      try {
        final capturedType = await FileSystemEntity.type(
          captured.path,
          followLinks: false,
        );
        // 符号链接只删除捕获的链接；异常目录不递归清理其未知内容。
        if (capturedType == FileSystemEntityType.file ||
            capturedType == FileSystemEntityType.link) {
          await captured.delete();
        }
        await capturedDirectory.delete();
      } catch (_) {
        throw const ValidationFailure();
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
    ProtocolObservation? observation,
    bool? windowVisible,
    bool? trayAvailable,
  }) => jsonEncode({
    'identity': 'xduwlan-recovery-validation',
    'event': event.name,
    if (report != null) 'report': DiagnosticRecord.fromReport(report).toJson(),
    if (observation != null) 'protocolObservation': observation.toJson(),
    'counts': counters.toJson(),
    if (phase != null) 'phase': phase.name,
    'windowVisible': ?windowVisible,
    'trayAvailable': ?trayAvailable,
  });
}

class CountingTransport implements PortalTransport {
  CountingTransport(this.inner, this.counters, {this.observationSink});
  final PortalTransport inner;
  final ValidationCounters counters;
  final ProtocolObservationSink? observationSink;
  @override
  Future<PortalResponse> request(
    String method,
    Uri url,
    OperationScope scope,
  ) async {
    counters.requests++;
    observationSink?.request();
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
  Future<Object> check(OperationScope scope) {
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
