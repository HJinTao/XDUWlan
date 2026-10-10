import 'package:flutter/foundation.dart';

import '../core/domain.dart';
import 'recovery_service.dart';

/// 界面状态只保留安全结果；一切手动操作通过此入口串行执行。
class RecoveryController extends ChangeNotifier {
  RecoveryController({required this.service, required this.store});
  final RecoveryService service;
  final CredentialStore store;
  bool busy = false;
  NetworkState network = NetworkState.unknown;
  RecoveryStage? stage;
  FailureCode? failure;
  RecoveryOutcome? outcome;
  OperationScope? _scope;
  bool _foreground = true;
  bool _disposed = false;
  int _generation = 0;

  Future<void> refresh() => _operate(false);
  Future<void> login() => _operate(true);

  Future<Credentials?> loadAccount() async {
    if (_disposed) return null;
    failure = null;
    try {
      return await store.load();
    } on AppFailure catch (error) {
      failure = error.code;
      notifyListeners();
      return null;
    } catch (_) {
      failure = FailureCode.credentialFileUnavailable;
      notifyListeners();
      return null;
    }
  }

  Future<void> _operate(bool authenticate) async {
    if (busy || !_foreground || _disposed) return;
    final generation = ++_generation;
    final scope = OperationScope();
    _scope = scope;
    busy = true;
    stage = RecoveryStage.checking;
    failure = null;
    outcome = null;
    notifyListeners();
    bool current() => !_disposed && generation == _generation;
    try {
      if (authenticate) {
        final result = await service.login(
          scope,
          onStage: (value) {
            if (!current()) return;
            stage = value;
            notifyListeners();
          },
        );
        if (!current()) return;
        network = result.network;
        failure = result.failure;
        outcome = result.outcome;
      } else {
        final result = await scope.run(() => service.check(scope));
        if (!current()) return;
        network = result;
      }
    } on AppFailure catch (error) {
      if (current()) {
        network = NetworkState.unknown;
        failure = error.code;
      }
    } catch (_) {
      if (current()) {
        network = NetworkState.unknown;
        failure = FailureCode.networkUnavailable;
      }
    } finally {
      scope.finish();
      if (current()) {
        _scope = null;
        stage = null;
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<bool> saveAccount(Credentials credentials) async {
    if (busy || _disposed) return false;
    try {
      validateCredentials(credentials);
    } on AppFailure catch (error) {
      failure = error.code;
      notifyListeners();
      return false;
    }
    busy = true;
    failure = null;
    notifyListeners();
    try {
      await store.save(
        Credentials(
          credentials.username.trim(),
          credentials.password,
          operatorSuffix: credentials.operatorSuffix,
        ),
      );
      if (_disposed) return false;
      return true;
    } catch (_) {
      if (!_disposed) failure = FailureCode.credentialFileUnavailable;
      return false;
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  void setForeground(bool foreground) {
    _foreground = foreground;
    if (foreground || _disposed || _scope == null) return;
    ++_generation;
    final submitted = _scope!.submitted;
    _scope!.cancel();
    _scope = null;
    busy = false;
    stage = null;
    network = NetworkState.unknown;
    outcome = RecoveryOutcome.cancelled;
    failure = submitted
        ? FailureCode.submittedUnconfirmed
        : FailureCode.cancelled;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _scope?.cancel();
    super.dispose();
  }
}
