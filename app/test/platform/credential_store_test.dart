import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xduwlan_app/core/domain.dart';
import 'package:xduwlan_app/platform/credential_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  String? stored;
  bool deny = false;
  final keys = <String>[];
  setUp(() {
    stored = null;
    deny = false;
    keys.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (deny) throw PlatformException(code: 'denied');
          final args = Map<String, dynamic>.from(call.arguments as Map);
          keys.add(args['key'] as String);
          if (call.method == 'write') stored = args['value'] as String;
          if (call.method == 'read') return stored;
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('账号以固定键单条安全记录读写，保留后缀', () async {
    final store = SystemCredentialStore();
    await store.save(
      const Credentials('fake-user', 'fake-password', operatorSuffix: '@fake'),
    );
    expect(jsonDecode(stored!)['username'], 'fake-user');
    final loaded = await store.load();
    expect(loaded!.password, 'fake-password');
    expect(loaded.operatorSuffix, '@fake');
    expect(keys.toSet(), {SystemCredentialStore.recordKey});
    expect(keys, isNot(contains('fake-user')));
  });

  test('缺失返回空，损坏与后端拒绝均为安全错误', () async {
    final store = SystemCredentialStore();
    expect(await store.load(), isNull);
    stored = '["fake-private"]';
    await expectLater(store.load(), throwsA(isA<AppFailure>()));
    deny = true;
    await expectLater(
      store.save(const Credentials('fake-user', 'fake-password')),
      throwsA(
        isA<AppFailure>().having(
          (e) => e.code,
          'code',
          FailureCode.credentialStoreUnavailable,
        ),
      ),
    );
  });
}
