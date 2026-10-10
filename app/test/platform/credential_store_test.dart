import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xduwlan_app/core/domain.dart';
import 'package:xduwlan_app/platform/credential_store.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('xduwlan-credentials-');
  });
  tearDown(() => directory.delete(recursive: true));

  test('账号以固定本地文件单条记录读写，保留后缀', () async {
    final store = LocalCredentialStore(directory: directory);
    await store.save(
      const Credentials('fake-user', 'fake-password', operatorSuffix: '@fake'),
    );
    final loaded = await store.load();
    expect(loaded!.password, 'fake-password');
    expect(loaded.operatorSuffix, '@fake');
    expect(await File('${directory.path}/credentials.json').exists(), isTrue);
  });

  test('缺失返回空，损坏与文件写入失败均为普通配置错误', () async {
    final store = LocalCredentialStore(directory: directory);
    expect(await store.load(), isNull);
    await File('${directory.path}/credentials.json')
        .writeAsString('["fake-private"]');
    await expectLater(store.load(), throwsA(isA<AppFailure>()));
    final invalidStore = LocalCredentialStore(file: File(directory.path));
    await expectLater(
      invalidStore.save(const Credentials('fake-user', 'fake-password')),
      throwsA(
        isA<AppFailure>().having(
          (e) => e.code,
          'code',
          FailureCode.credentialFileUnavailable,
        ),
      ),
    );
  });
}
