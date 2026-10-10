import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xduwlan_app/core/domain.dart';

void main() {
  test('同步任务耗尽截止时间时也消费其失败 Future', () async {
    final scope = _SynchronouslyExpiredScope();
    var actionEntered = false;
    Future<void> start() async {
      await scope.run(() {
        // 精确模拟同步任务耗尽预算，不依赖首次 JIT 是否赶上 2ms 窗口。
        actionEntered = true;
        scope.expired = true;
        return Future<void>.error(const AppFailure(FailureCode.protocol));
      });
    }

    await expectLater(
      start(),
      throwsA(
        isA<AppFailure>().having(
          (error) => error.code,
          'code',
          FailureCode.protocol,
        ),
      ),
    );
    expect(actionEntered, isTrue);
    expect(scope.remaining, Duration.zero);
    scope.finish();
  });

  test('取消会中止等待并释放已注册的资源', () async {
    final scope = OperationScope();
    var released = 0;
    scope.onCancel(() => released++);
    final pending = scope.run(() => Completer<void>().future);
    final expectation = expectLater(
      pending,
      throwsA(
        isA<AppFailure>().having((e) => e.code, 'code', FailureCode.cancelled),
      ),
    );
    scope.cancel();
    await expectation;
    expect(released, 1);
    expect(scope.ensureActive, throwsA(isA<AppFailure>()));
    scope.cancel();
    expect(released, 1);
  });

  test('截止时间终止挂起操作', () async {
    final scope = OperationScope(budget: const Duration(milliseconds: 10));
    await expectLater(
      scope.run(() => Completer<void>().future),
      throwsA(
        isA<AppFailure>().having((e) => e.code, 'code', FailureCode.timeout),
      ),
    );
    expect(scope.remaining, Duration.zero);
  });

  test('完成后撤销截止计时并可注销资源回调', () async {
    final scope = OperationScope();
    var released = false;
    final unregister = scope.onCancel(() => released = true);
    expect(await scope.run(() => Future.value(7)), 7);
    unregister();
    scope.markSubmitted();
    expect(scope.submitted, isTrue);
    scope.finish();
    expect(released, isFalse);
  });

  test('秘密对象的文本摘要不包含输入', () {
    expect(
      const Credentials('fake-user', 'fake-secret').toString(),
      isNot(contains('fake-user')),
    );
    expect(
      PortalContext(
        Uri.parse('https://portal.invalid'),
        '192.0.2.1',
        '1',
      ).toString(),
      isNot(contains('192.0.2.1')),
    );
    expect(
      const PortalResponse(
        200,
        'fake-secret',
        location: 'https://portal.invalid',
      ).toString(),
      isNot(contains('fake-secret')),
    );
  });
}

/// 只在同步任务内令剩余预算归零，真实截止与资源释放仍由独立用例验证。
class _SynchronouslyExpiredScope extends OperationScope {
  bool expired = false;
  @override
  Duration get remaining => expired ? Duration.zero : super.remaining;
}
