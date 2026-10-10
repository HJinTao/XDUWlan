import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xduwlan_app/application/settings.dart';

void main() {
  late Directory directory;
  late File settingsFile;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('xduwlan-settings-');
    settingsFile = File('${directory.path}/settings.json');
  });
  tearDown(() => directory.delete(recursive: true));

  test('缺失配置使用默认开关，读取不创建文件', () async {
    final settings = await LocalSettingsStore(directory: directory).load();
    expect(settings.automaticRecoveryEnabled, isTrue);
    expect(settings.launchAtStartup, isFalse);
    expect(await directory.list().toList(), isEmpty);
  });

  test('两个开关逐次修改后可由新存储实例准确读取', () async {
    final store = LocalSettingsStore(directory: directory);
    final credentialFile = File('${directory.path}/credentials.json');
    await credentialFile.writeAsString('fake-credential-sentinel');
    await store.save(
      const AppSettings(automaticRecoveryEnabled: false, launchAtStartup: true),
    );
    var loaded = await LocalSettingsStore(directory: directory).load();
    expect(loaded.automaticRecoveryEnabled, isFalse);
    expect(loaded.launchAtStartup, isTrue);
    await store.save(loaded.copyWith(automaticRecoveryEnabled: true));
    loaded = await LocalSettingsStore(directory: directory).load();
    expect(loaded.automaticRecoveryEnabled, isTrue);
    expect(loaded.launchAtStartup, isTrue);
    expect(jsonDecode(await settingsFile.readAsString()), {
      'automaticRecoveryEnabled': true,
      'launchAtStartup': true,
    });
    expect(await credentialFile.readAsString(), 'fake-credential-sentinel');
  });

  for (final invalid in [
    'fake-private-invalid-json',
    '[]',
    '{"automaticRecoveryEnabled":false}',
    '{"automaticRecoveryEnabled":"false","launchAtStartup":false}',
    '{"automaticRecoveryEnabled":false,"launchAtStartup":false,"extra":"fake-private"}',
  ]) {
    test('损坏配置仅抛出不含原文和路径的安全错误：$invalid', () async {
      await settingsFile.writeAsString(invalid);
      await expectLater(
        LocalSettingsStore(directory: directory).load(),
        throwsA(
          isA<FormatException>()
              .having((error) => error.source, 'source', isNull)
              .having(
                (error) => error.toString(),
                'message',
                allOf(
                  isNot(contains('fake-private')),
                  isNot(contains(directory.path)),
                ),
              ),
        ),
      );
      expect(await settingsFile.readAsString(), invalid);
    });
  }

  test('目标为目录时读取失败而非误判为缺失配置', () async {
    await expectLater(
      LocalSettingsStore(file: File(directory.path)).load(),
      throwsA(
        isA<FormatException>().having(
          (error) => error.toString(),
          'message',
          isNot(contains(directory.path)),
        ),
      ),
    );
  });

  test('配置写入失败保留原有完整文件且错误不含文件路径', () async {
    final initial = jsonEncode({
      'automaticRecoveryEnabled': false,
      'launchAtStartup': false,
    });
    await settingsFile.writeAsString(initial);
    await Directory('${settingsFile.path}.tmp').create();
    await expectLater(
      LocalSettingsStore(directory: directory).save(const AppSettings()),
      throwsA(
        isA<FileSystemException>().having(
          (error) => error.toString(),
          'message',
          isNot(contains(directory.path)),
        ),
      ),
    );
    expect(await settingsFile.readAsString(), initial);
  });

  test('超大配置作为损坏处理并隐藏原文', () async {
    await settingsFile.writeAsString('${' ' * (128 * 1024)}{}');
    await expectLater(
      LocalSettingsStore(directory: directory).load(),
      throwsA(isA<FormatException>().having((e) => e.source, 'source', isNull)),
    );
  });

  test('同时保存与读取按调用顺序完成且没有残留临时文件', () async {
    final store = LocalSettingsStore(directory: directory);
    final saving = store.save(
      const AppSettings(automaticRecoveryEnabled: false, launchAtStartup: true),
    );
    final loading = store.load();
    await saving;
    final loaded = await loading;
    expect(loaded.automaticRecoveryEnabled, isFalse);
    expect(loaded.launchAtStartup, isTrue);
    expect(await File('${settingsFile.path}.tmp').exists(), isFalse);
  });
}
