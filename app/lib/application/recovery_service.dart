import '../core/domain.dart';

/// 一次恢复仅在可信上下文取得后读取密码，成功后独立复查。
class RecoveryService {
  RecoveryService({
    required this.probe,
    required this.portal,
    required this.store,
  });
  final NetworkProbe probe;
  final PortalClient portal;
  final CredentialStore store;

  Future<NetworkState> check(OperationScope scope) => probe.check(scope);

  Future<RecoveryResult> login(
    OperationScope scope, {
    void Function(RecoveryStage)? onStage,
  }) async {
    var network = NetworkState.unknown;
    try {
      scope.ensureActive();
      onStage?.call(RecoveryStage.checking);
      network = await scope.run(() => probe.check(scope));
      scope.ensureActive();
      if (network == NetworkState.online) {
        return RecoveryResult(RecoveryOutcome.alreadyOnline, network);
      }
      if (network != NetworkState.portalRequired) {
        return RecoveryResult(
          RecoveryOutcome.failed,
          network,
          failure: network == NetworkState.unavailable
              ? FailureCode.networkUnavailable
              : FailureCode.protocol,
        );
      }
      onStage?.call(RecoveryStage.preparing);
      final context = await scope.run(() => portal.prepare(scope));
      scope.ensureActive();
      final credentials = await scope.run(() => store.load());
      scope.ensureActive();
      if (credentials == null) {
        throw const AppFailure(FailureCode.credentialsMissing);
      }
      validateCredentials(credentials);
      final username = credentials.username.trim();
      final suffix = credentials.operatorSuffix;
      final effective = Credentials(
        suffix.isNotEmpty && !username.endsWith(suffix)
            ? '$username$suffix'
            : username,
        credentials.password,
      );
      onStage?.call(RecoveryStage.authenticating);
      await scope.run(
        () => portal.authenticate(
          context,
          effective,
          scope,
          beforeSubmit: () async {
            scope.markSubmitted();
          },
        ),
      );
      scope.ensureActive();
      onStage?.call(RecoveryStage.verifying);
      network = await scope.run(() => probe.check(scope));
      scope.ensureActive();
      if (network == NetworkState.online) {
        return RecoveryResult(RecoveryOutcome.restored, network);
      }
      return RecoveryResult(
        RecoveryOutcome.failed,
        network,
        failure: FailureCode.verificationFailed,
      );
    } on AppFailure catch (error) {
      final uncertain =
          scope.submitted &&
          {
            FailureCode.timeout,
            FailureCode.cancelled,
            FailureCode.networkUnavailable,
          }.contains(error.code);
      return RecoveryResult(
        error.code == FailureCode.cancelled
            ? RecoveryOutcome.cancelled
            : RecoveryOutcome.failed,
        network,
        failure: uncertain ? FailureCode.submittedUnconfirmed : error.code,
      );
    } catch (_) {
      return RecoveryResult(
        RecoveryOutcome.failed,
        network,
        failure: scope.submitted
            ? FailureCode.submittedUnconfirmed
            : FailureCode.protocol,
      );
    }
  }
}
