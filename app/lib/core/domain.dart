/// 安全结果、短期认证数据与可替换的外部能力。
library;

import 'dart:async';

enum NetworkState { online, portalRequired, unavailable, unknown }

/// 设备当前使用的链路类型。只保留可用于安全决策的类别，不保存地址。
enum NetworkLink { cellular, wifi, wired, other, none, unknown }

/// 校园网络身份状态，与普通互联网可达性分开表示。
enum CampusNetworkState {
  unconfirmed,
  authenticationRequired,
  online,
  unavailable,
  unknown,
}

enum FailureCode {
  credentialsMissing,
  credentialsInvalid,
  credentialStoreUnavailable,
  credentialFileUnavailable,
  networkUnavailable,
  protocol,
  authRejected,
  verificationFailed,
  cancelled,
  timeout,
  submittedUnconfirmed,
  authenticationNotAllowed,
}

enum RecoveryStage { checking, preparing, authenticating, verifying }

enum RecoveryOutcome { alreadyOnline, restored, failed, cancelled }

enum OperationSource { manual, automatic, tray, background }

enum OperationKind { check, authenticate }

class OperationReport {
  const OperationReport({
    required this.kind,
    required this.source,
    required this.network,
    required this.outcome,
    required this.failure,
    required this.elapsed,
    required this.completedAt,
    this.link,
    this.campus,
    this.authenticationAllowed,
  });

  final OperationKind kind;
  final OperationSource source;
  final NetworkState network;
  final RecoveryOutcome? outcome;
  final FailureCode? failure;
  final Duration elapsed;
  final DateTime completedAt;
  final NetworkLink? link;
  final CampusNetworkState? campus;
  final bool? authenticationAllowed;
}

class AppFailure implements Exception {
  const AppFailure(this.code);
  final FailureCode code;
  @override
  String toString() => 'AppFailure(${code.name})';
}

class Credentials {
  const Credentials(this.username, this.password, {this.operatorSuffix = ''});
  final String username;
  final String password;
  final String operatorSuffix;
  @override
  String toString() => 'Credentials(<redacted>)';
}

class PortalContext {
  const PortalContext(this.origin, this.ip, this.acid);
  final Uri origin;
  final String ip;
  final String acid;
  @override
  String toString() => 'PortalContext(<redacted>)';
}

class PortalResponse {
  const PortalResponse(this.statusCode, this.body, {this.location});
  final int statusCode;
  final String body;
  final String? location;
  @override
  String toString() => 'PortalResponse($statusCode, <redacted>)';
}

class RecoveryResult {
  const RecoveryResult(
    this.outcome,
    this.network, {
    this.failure,
    this.observation,
  });
  final RecoveryOutcome outcome;
  final NetworkState network;
  final FailureCode? failure;
  final NetworkObservation? observation;
}

abstract interface class CredentialStore {
  Future<Credentials?> load();
  Future<void> save(Credentials credentials);
}

abstract interface class NetworkProbe {
  /// 新实现返回 [NetworkObservation]，旧实现可继续返回 [NetworkState]。
  Future<Object> check(OperationScope scope);
}

/// 网络事实与 Portal 探测结果的共享值对象。
class NetworkObservation {
  const NetworkObservation({
    required this.link,
    required this.campus,
    required this.portal,
    required this.authenticationAllowed,
  });

  final NetworkLink link;
  final CampusNetworkState campus;
  final NetworkState portal;
  final bool authenticationAllowed;

  /// 让旧 fake 在迁移期间继续提供安全的默认观察结果。
  factory NetworkObservation.fromLegacy(NetworkState state) =>
      NetworkObservation(
        link: switch (state) {
          NetworkState.portalRequired => NetworkLink.wifi,
          NetworkState.online => NetworkLink.unknown,
          NetworkState.unavailable => NetworkLink.none,
          NetworkState.unknown => NetworkLink.unknown,
        },
        campus: switch (state) {
          NetworkState.portalRequired =>
            CampusNetworkState.authenticationRequired,
          NetworkState.online => CampusNetworkState.online,
          NetworkState.unavailable => CampusNetworkState.unavailable,
          NetworkState.unknown => CampusNetworkState.unknown,
        },
        portal: state,
        // 旧探测器没有链路事实；保留旧认证行为，直到其升级为新观察器。
        authenticationAllowed: state == NetworkState.portalRequired,
      );

  NetworkObservation copyWith({
    NetworkLink? link,
    CampusNetworkState? campus,
    NetworkState? portal,
    bool? authenticationAllowed,
  }) => NetworkObservation(
    link: link ?? this.link,
    campus: campus ?? this.campus,
    portal: portal ?? this.portal,
    authenticationAllowed: authenticationAllowed ?? this.authenticationAllowed,
  );

  @override
  bool operator ==(Object other) => other is NetworkObservation
      ? other.link == link &&
            other.campus == campus &&
            other.portal == portal &&
            other.authenticationAllowed == authenticationAllowed
      : other is NetworkState && other == portal;

  @override
  int get hashCode => Object.hash(link, campus, portal, authenticationAllowed);
}

abstract interface class PortalTransport {
  Future<PortalResponse> request(String method, Uri url, OperationScope scope);
}

abstract interface class PortalClient {
  Future<PortalContext> prepare(OperationScope scope);
  Future<void> authenticate(
    PortalContext context,
    Credentials credentials,
    OperationScope scope, {
    required Future<void> Function() beforeSubmit,
  });
}

/// 一轮操作共享截止时间和取消信号，适配器注册资源释放回调。
class OperationScope {
  OperationScope({this.budget = const Duration(seconds: 45)}) {
    _clock.start();
    _deadline = Timer(budget, () => cancel(FailureCode.timeout));
  }
  final Duration budget;
  final Stopwatch _clock = Stopwatch();
  final Set<void Function()> _listeners = {};
  Timer? _deadline;
  FailureCode? _cancelReason;
  bool _finished = false;
  bool _submitted = false;
  bool get submitted => _submitted;
  void markSubmitted() {
    ensureActive();
    _submitted = true;
  }

  bool get isCancelled => _cancelReason != null;
  Duration get remaining {
    final value = budget - _clock.elapsed;
    return value.isNegative || isCancelled ? Duration.zero : value;
  }

  void ensureActive() {
    if (_cancelReason != null) throw AppFailure(_cancelReason!);
    if (_finished) throw const AppFailure(FailureCode.cancelled);
    if (remaining == Duration.zero) {
      cancel(FailureCode.timeout);
      throw const AppFailure(FailureCode.timeout);
    }
  }

  void cancel([FailureCode reason = FailureCode.cancelled]) {
    if (isCancelled || _finished) return;
    _cancelReason = reason;
    _deadline?.cancel();
    final callbacks = List.of(_listeners);
    _listeners.clear();
    for (final callback in callbacks) {
      callback();
    }
  }

  void finish() {
    _finished = true;
    _deadline?.cancel();
    _clock.stop();
    _listeners.clear();
  }

  void Function() onCancel(void Function() callback) {
    if (isCancelled) {
      callback();
      return () {};
    }
    ensureActive();
    _listeners.add(callback);
    return () => _listeners.remove(callback);
  }

  Future<T> run<T>(Future<T> Function() action) {
    ensureActive();
    final result = Completer<T>();
    void Function()? unregister;
    try {
      unregister = onCancel(() {
        if (!result.isCompleted) {
          result.completeError(AppFailure(_cancelReason!));
        }
      });
      ensureActive();
      // 直接调用 action，确保已完成失败 Future 立即绑定错误监听器。
      final work = action();
      work.then(
        (value) {
          unregister?.call();
          if (result.isCompleted) return;
          try {
            ensureActive();
            result.complete(value);
          } on AppFailure catch (error) {
            result.completeError(error);
          }
        },
        onError: (Object error, StackTrace stack) {
          unregister?.call();
          if (!result.isCompleted) result.completeError(error, stack);
        },
      );
    } catch (error, stack) {
      unregister?.call();
      if (!result.isCompleted) result.completeError(error, stack);
    }
    return result.future;
  }
}

/// 不修剪密码，拒绝无法可靠编码或控制字符输入。
void validateCredentials(Credentials credentials) {
  if (credentials.username.trim().isEmpty ||
      credentials.password.isEmpty ||
      !_validText(credentials.username) ||
      !_validText(credentials.password) ||
      (credentials.operatorSuffix.isNotEmpty &&
          !RegExp(r'^@[A-Za-z0-9._-]{1,32}$')
              .hasMatch(credentials.operatorSuffix))) {
    throw const AppFailure(FailureCode.credentialsInvalid);
  }
}

bool _validText(String value) {
  final units = value.codeUnits;
  for (var index = 0; index < units.length; index++) {
    final unit = units[index];
    if (unit < 32 || unit == 127) return false;
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++index >= units.length ||
          units[index] < 0xdc00 ||
          units[index] > 0xdfff) {
        return false;
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    }
  }
  return true;
}
