import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/domain.dart';
import 'recovery_service.dart';

/// 所有来源的检查与认证共享同一个串行门闩，仅保留一个待执行意图。
class RecoveryController extends ChangeNotifier {
  RecoveryController({required this.service, required this.store});
  final RecoveryService service;
  final CredentialStore store;
  bool busy = false;
  bool accountSaving = false;
  NetworkState network = NetworkState.unknown;
  NetworkLink link = NetworkLink.unknown;
  CampusNetworkState campus = CampusNetworkState.unknown;
  bool authenticationAllowed = false;
  RecoveryStage? stage;
  FailureCode? failure;
  FailureCode? accountFailure;
  RecoveryOutcome? outcome;
  OperationReport? lastReport;
  DateTime? lastCheckAt;
  DateTime? lastAuthenticateAt;
  FailureCode? lastFailure;
  int accountRevision = 0;
  int operationSequence = 0;
  OperationKind? activeKind;
  OperationSource? activeSource;
  OperationScope? _scope;
  _Intent? _pending;
  bool _stopped = false;
  bool _disposed = false;
  bool get manualPending => _pending != null;

  Future<OperationReport?> refresh() =>
      run(OperationKind.check, OperationSource.manual);
  Future<OperationReport?> login() =>
      run(OperationKind.authenticate, OperationSource.manual);

  Future<OperationReport?> run(
    OperationKind kind,
    OperationSource source, {
    bool allowAuthentication = false,
  }) {
    if (_stopped) return Future.value(null);
    final intent = _Intent(kind, source, allowAuthentication);
    if (busy) {
      if (source == OperationSource.automatic) return Future.value(null);
      if (_pending == null) {
        _pending = intent;
      } else {
        _pending!.kind = kind;
        _pending!.source = source;
        _pending!.waiters.addAll(intent.waiters);
      }
      notifyListeners();
    } else {
      busy = true;
      unawaited(_drain(intent));
    }
    return intent.waiters.first.future;
  }

  Future<void> _drain(_Intent intent) async {
    var current = intent;
    while (true) {
      final report = await _execute(current);
      for (final waiter in current.waiters) {
        waiter.complete(report);
      }
      if (_stopped || _pending == null) break;
      current = _pending!;
      _pending = null;
    }
    busy = false;
    stage = null;
    activeKind = null;
    activeSource = null;
    if (!_disposed) notifyListeners();
  }

  Future<OperationReport> _execute(_Intent intent) async {
    operationSequence++;
    activeKind = intent.kind;
    activeSource = intent.source;
    final scope = OperationScope();
    final elapsed = Stopwatch()..start();
    _scope = scope;
    stage = RecoveryStage.checking;
    failure = null;
    outcome = null;
    var kind = intent.kind;
    var resultNetwork = NetworkState.unknown;
    var resultLink = NetworkLink.unknown;
    var resultCampus = CampusNetworkState.unknown;
    var resultAuthenticationAllowed = false;
    FailureCode? resultFailure;
    RecoveryOutcome? resultOutcome;
    notifyListeners();
    try {
      if (intent.kind == OperationKind.authenticate ||
          intent.allowAuthentication) {
        final result = await service.login(
          scope,
          onStage: (value) {
            if (value == RecoveryStage.preparing) {
              kind = OperationKind.authenticate;
            }
            if (_disposed) return;
            stage = value;
            notifyListeners();
          },
        );
        resultNetwork = result.network;
        resultLink = result.observation?.link ?? NetworkLink.unknown;
        resultCampus = result.observation?.campus ?? CampusNetworkState.unknown;
        resultAuthenticationAllowed =
            result.observation?.authenticationAllowed ?? false;
        resultFailure = result.failure;
        resultOutcome = kind == OperationKind.authenticate
            ? result.outcome
            : null;
      } else {
        final observation = await scope.run(() => service.check(scope));
        resultNetwork = observation.portal;
        resultLink = observation.link;
        resultCampus = observation.campus;
        resultAuthenticationAllowed = observation.authenticationAllowed;
        resultFailure = switch (resultNetwork) {
          NetworkState.unavailable => FailureCode.networkUnavailable,
          NetworkState.unknown => FailureCode.protocol,
          _ => null,
        };
      }
    } on AppFailure catch (error) {
      resultFailure = scope.submitted
          ? FailureCode.submittedUnconfirmed
          : error.code;
      if (error.code == FailureCode.cancelled) {
        resultOutcome = RecoveryOutcome.cancelled;
      }
    } catch (_) {
      resultFailure = FailureCode.networkUnavailable;
    } finally {
      scope.finish();
      _scope = null;
      elapsed.stop();
    }
    final report = OperationReport(
      kind: kind,
      source: intent.source,
      network: resultNetwork,
      outcome: resultOutcome,
      failure: resultFailure,
      elapsed: elapsed.elapsed,
      completedAt: DateTime.now(),
      link: resultLink,
      campus: resultCampus,
      authenticationAllowed: resultAuthenticationAllowed,
    );
    if (!_disposed) {
      network = report.network;
      link = report.link ?? NetworkLink.unknown;
      campus = report.campus ?? CampusNetworkState.unknown;
      authenticationAllowed = report.authenticationAllowed ?? false;
      failure = report.failure;
      outcome = report.outcome;
      lastReport = report;
      lastCheckAt = report.completedAt;
      if (kind == OperationKind.authenticate) {
        lastAuthenticateAt = report.completedAt;
      }
      if (report.failure != null) lastFailure = report.failure;
      notifyListeners();
    }
    return report;
  }

  Future<Credentials?> loadAccount() async {
    if (_stopped) return null;
    accountFailure = null;
    try {
      return await store.load();
    } on AppFailure catch (error) {
      accountFailure = error.code;
    } catch (_) {
      accountFailure = FailureCode.credentialFileUnavailable;
    }
    if (!_disposed) notifyListeners();
    return null;
  }

  Future<bool> saveAccount(Credentials credentials) async {
    if (_stopped || accountSaving) return false;
    accountFailure = null;
    try {
      validateCredentials(credentials);
    } on AppFailure catch (error) {
      accountFailure = error.code;
      if (!busy) failure = error.code;
      notifyListeners();
      return false;
    }
    accountSaving = true;
    notifyListeners();
    try {
      await store.save(
        Credentials(
          credentials.username.trim(),
          credentials.password,
          operatorSuffix: credentials.operatorSuffix,
        ),
      );
      if (_stopped) return false;
      accountRevision++;
      return true;
    } catch (_) {
      accountFailure = FailureCode.credentialFileUnavailable;
      if (!busy) failure = accountFailure;
      return false;
    } finally {
      accountSaving = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// 窗口可见性不改变网络任务生命周期，保留旧接口以兼容调用方。
  void setForeground(bool foreground) {}

  void shutdown() {
    if (_stopped) return;
    _stopped = true;
    _scope?.cancel();
    final pending = _pending;
    _pending = null;
    for (final waiter in pending?.waiters ?? <Completer<OperationReport?>>[]) {
      waiter.complete(null);
    }
  }

  @override
  void dispose() {
    shutdown();
    _disposed = true;
    super.dispose();
  }
}

class _Intent {
  _Intent(this.kind, this.source, this.allowAuthentication);
  OperationKind kind;
  OperationSource source;
  final bool allowAuthentication;
  final waiters = [Completer<OperationReport?>()];
}
