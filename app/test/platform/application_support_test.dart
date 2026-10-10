import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// 使用 path_provider 的平台替身，仅返回测试临时目录。
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:xduwlan_app/application/diagnostics.dart';
import 'package:xduwlan_app/application/settings.dart';
import 'package:xduwlan_app/core/domain.dart';
import 'package:xduwlan_app/platform/application_support.dart';
import 'package:xduwlan_app/platform/credential_store.dart';

class _SupportProvider extends PathProviderPlatform {
  _SupportProvider(this.directory);

  final Directory directory;
  int calls = 0;

  @override
  Future<String?> getApplicationSupportPath() async {
    calls++;
    return directory.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory home;
  late Directory regular;
  late Directory legacy;
  late PathProviderPlatform originalProvider;
  late _SupportProvider provider;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('xduwlan-support-');
    regular = Directory(
      '${home.path}/Library/Application Support/cn.xduwlan.desktop',
    );
    legacy = Directory(
      '${home.path}/Library/Containers/cn.xduwlan.desktop/Data/'
      'Library/Application Support/cn.xduwlan.desktop',
    );
    originalProvider = PathProviderPlatform.instance;
    provider = _SupportProvider(regular);
    PathProviderPlatform.instance = provider;
  });
  tearDown(() async {
    PathProviderPlatform.instance = originalProvider;
    await home.delete(recursive: true);
  });

  test('macOS 已有容器目录优先使用，两个目录的现有文件均不迁移', () async {
    await regular.create(recursive: true);
    await legacy.create(recursive: true);
    final oldFile = File('${legacy.path}/credentials.json');
    final newFile = File('${regular.path}/credentials.json');
    await oldFile.writeAsString('fake-legacy-sentinel');
    await newFile.writeAsString('fake-regular-sentinel');

    final selected = await resolveApplicationSupportDirectory(
      supportDirectory: regular,
      macOS: true,
    );

    expect(
      selected.absolute.uri.normalizePath(),
      legacy.absolute.uri.normalizePath(),
    );
    expect(await oldFile.readAsString(), 'fake-legacy-sentinel');
    expect(await newFile.readAsString(), 'fake-regular-sentinel');
    expect(provider.calls, 0);
  });

  test('macOS 仅有空容器目录仍继续原位置，不以凭据内容决定目录', () async {
    await legacy.create(recursive: true);
    final selected = await resolveApplicationSupportDirectory(
      supportDirectory: regular,
      macOS: true,
    );
    expect(
      selected.absolute.uri.normalizePath(),
      legacy.absolute.uri.normalizePath(),
    );
    expect(await legacy.list().toList(), isEmpty);
    expect(await regular.exists(), isFalse);
  });

  test('macOS 新安装返回常规目录，解析阶段不创建任何目录', () async {
    final selected = await resolveApplicationSupportDirectory(
      supportDirectory: regular,
      macOS: true,
    );
    expect(selected, same(regular));
    expect(await home.list().toList(), isEmpty);
  });

  test('非 macOS 即使有类似容器目录也保留平台原始目录', () async {
    await legacy.create(recursive: true);
    final selected = await resolveApplicationSupportDirectory(
      supportDirectory: regular,
      macOS: false,
    );
    expect(selected, same(regular));
    expect(await regular.exists(), isFalse);
  });

  test('已在容器中的平台目录不再次嵌套查找', () async {
    final nestedTrap = Directory(
      '${home.path}/Library/Containers/cn.xduwlan.desktop/Data/'
      'Library/Containers/cn.xduwlan.desktop/Data/'
      'Library/Application Support/cn.xduwlan.desktop',
    );
    await nestedTrap.create(recursive: true);
    await legacy.create(recursive: true);
    final selected = await resolveApplicationSupportDirectory(
      supportDirectory: legacy,
      macOS: true,
    );
    expect(selected, same(legacy));
  });

  test('未识别的支持目录保持原样，不猜测用户根目录', () async {
    await legacy.create(recursive: true);
    final custom = Directory('${home.path}/custom-support/cn.xduwlan.desktop');
    final selected = await resolveApplicationSupportDirectory(
      supportDirectory: custom,
      macOS: true,
    );
    expect(selected, same(custom));
    expect(await custom.exists(), isFalse);
  });

  test('只有实际解析默认目录时才请求平台路径', () async {
    LocalCredentialStore();
    LocalSettingsStore();
    LocalDiagnosticStore();
    expect(provider.calls, 0);
    final selected = await resolveApplicationSupportDirectory(macOS: false);
    expect(selected.path, regular.path);
    expect(provider.calls, 1);
  });

  test('三个默认存储共享兼容目录，旧虚构数据保持原格式', () async {
    await legacy.create(recursive: true);
    final oldCredentials = File('${legacy.path}/credentials.json');
    final credentialData = jsonEncode({
      'username': 'fake-legacy-user',
      'password': 'fake-legacy-password',
      'operatorSuffix': '@fake',
    });
    await oldCredentials.writeAsString(credentialData);
    await File('${legacy.path}/settings.json').writeAsString(
      '{"automaticRecoveryEnabled":false,"launchAtStartup":true}',
    );
    await File('${legacy.path}/diagnostics.json').writeAsString(
      '[{"time":"2026-10-10T00:00:00.000Z","source":"manual",'
      '"action":"check","network":"online","elapsedMilliseconds":12}]',
    );

    final credentials = await LocalCredentialStore().load();
    final settings = await LocalSettingsStore().load();
    final diagnostics = await LocalDiagnosticStore().load();

    if (Platform.isMacOS) {
      expect(credentials?.username, 'fake-legacy-user');
      expect(credentials?.operatorSuffix, '@fake');
      expect(settings.automaticRecoveryEnabled, isFalse);
      expect(settings.launchAtStartup, isTrue);
      expect(diagnostics.single.elapsedMilliseconds, 12);
    } else {
      expect(credentials, isNull);
      expect(settings.automaticRecoveryEnabled, isTrue);
      expect(settings.launchAtStartup, isFalse);
      expect(diagnostics, isEmpty);
    }
    expect(await oldCredentials.readAsString(), credentialData);
    expect(await regular.exists(), isFalse);
  });

  test('存储显式注入的目录和文件不触发兼容重定向或平台查询', () async {
    await legacy.create(recursive: true);
    await LocalCredentialStore(
      directory: regular,
    ).save(const Credentials('fake-injected-user', 'fake-injected-password'));
    await LocalSettingsStore(directory: regular)
        .save(const AppSettings(automaticRecoveryEnabled: false));
    await LocalDiagnosticStore(directory: regular).append(
      DiagnosticRecord(
        time: DateTime.utc(2026, 10, 10),
        source: OperationSource.manual,
        action: OperationKind.check,
        network: NetworkState.online,
        outcome: null,
        failure: null,
        elapsedMilliseconds: 1,
      ),
    );
    final credentialOverride = File('${home.path}/override-credentials.json');
    await LocalCredentialStore(file: credentialOverride)
        .save(const Credentials('fake-file-user', 'fake-file-password'));
    final settingsOverride = File('${home.path}/override-settings.json');
    await LocalSettingsStore(file: settingsOverride).save(const AppSettings());
    final diagnosticOverride = File('${home.path}/override-diagnostics.json');
    await LocalDiagnosticStore(file: diagnosticOverride).clear();

    expect(provider.calls, 0);
    expect(await File('${regular.path}/credentials.json').exists(), isTrue);
    expect(await File('${regular.path}/settings.json').exists(), isTrue);
    expect(await File('${regular.path}/diagnostics.json').exists(), isTrue);
    expect(await credentialOverride.exists(), isTrue);
    expect(await settingsOverride.exists(), isTrue);
    expect(await legacy.list().toList(), isEmpty);
  });
}
