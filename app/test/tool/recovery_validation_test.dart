import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xduwlan_app/application/app_runtime_controller.dart';
import 'package:xduwlan_app/application/diagnostics.dart';
import 'package:xduwlan_app/application/recovery_controller.dart';
import 'package:xduwlan_app/application/recovery_service.dart';
import 'package:xduwlan_app/application/settings.dart';
import 'package:xduwlan_app/core/domain.dart';

import '../../tool/recovery_validation_support.dart';
import '../application/runtime_fakes.dart';

void main() {
  test('未指定场景和敏感或未知参数均不能启动网络验证', () {
    expect(ValidationOptions.parse([]), isNull);
    for (final arguments in [
      ['--password=test-only-password'],
      ['--scenario=check', '--username=test-only-user'],
      ['--scenario=check', '--url=https://portal.invalid'],
      ['--scenario=unknown'],
      ['--scenario=check', '--scenario=authenticate'],
      ['--scenario=observe', '--duration-seconds=0'],
      ['--scenario=observe', '--duration-seconds=10801'],
      ['--scenario=check', '--directory=relative'],
      ['--scenario=check', '--directory=/tmp/test\nsecret'],
    ]) {
      expect(() => ValidationOptions.parse(arguments), throwsFormatException);
    }
    final options = ValidationOptions.parse([
      '--scenario=observe',
      '--directory=/tmp/test-only-validation',
      '--background',
      '--without-tray',
    ])!;
    expect(options.scenario, ValidationScenario.observe);
    expect(options.duration, const Duration(hours: 2));
    expect(options.background, isTrue);
    expect(options.withoutTray, isTrue);
  });

  test('独立验证目录拒绝产品记录和符号链接且保留原内容', () async {
    final parent = await Directory.systemTemp.createTemp('validation-test-');
    addTearDown(() => parent.delete(recursive: true));
    final directory = await Directory('${parent.path}/existing').create();
    final record = File('${directory.path}/credentials.json');
    await record.writeAsString('test-only-private-record');
    await expectLater(
      ValidationFiles.create(directory.path),
      throwsA(isA<ValidationFailure>()),
    );
    expect(await record.readAsString(), 'test-only-private-record');
    if (!Platform.isWindows) {
      final link = await Link('${parent.path}/linked').create(directory.path);
      await expectLater(
        ValidationFiles.create(link.path),
        throwsA(isA<ValidationFailure>()),
      );
    }
    final fresh = await ValidationFiles.create('${parent.path}/fresh');
    expect(await fresh.directory.exists(), isTrue);
    expect(await fresh.command.exists(), isFalse);
    final support = await Directory('${parent.path}/product-support').create();
    for (final path in [support.path, '${support.path}/validation']) {
      await expectLater(
        ValidationFiles.create(path, forbiddenDirectory: support),
        throwsA(isA<ValidationFailure>()),
      );
    }
    expect(await support.list().isEmpty, isTrue);
  });

  test('根目录检查后出现未知内容时只写入新建私有会话目录', () async {
    final parent = await Directory.systemTemp.createTemp('validation-root-');
    addTearDown(() => parent.delete(recursive: true));
    final root = await Directory('${parent.path}/root').create();
    final unknownSettings = File('${root.path}/settings.json');
    final unknownReports = File('${root.path}/reports.jsonl');
    final target = File('${parent.path}/untouched');
    await target.writeAsString('test-only-report-sentinel');
    Future<void> publishUnknownFiles() async {
      await unknownSettings.writeAsString('test-only-settings-sentinel');
      if (Platform.isWindows) {
        await unknownReports.writeAsString('test-only-report-sentinel');
      } else {
        await Link(unknownReports.path).create(target.path);
      }
    }

    final files = await IOOverrides.runWithIOOverrides(
      () => ValidationFiles.create(root.path),
      _ValidationRootRaceOverrides(root.path, publishUnknownFiles),
    );
    await LocalSettingsStore(directory: files.directory)
        .save(const AppSettings(automaticRecoveryEnabled: false));
    final log = files.reports.openWrite()..writeln('test-only-safe-report');
    await log.close();
    expect(await target.readAsString(), 'test-only-report-sentinel');
    expect(await unknownSettings.readAsString(), 'test-only-settings-sentinel');
    expect(await unknownReports.readAsString(), 'test-only-report-sentinel');
    expect(
      await FileSystemEntity.identical(files.directory.parent.path, root.path),
      isTrue,
    );
    expect(await files.reports.readAsString(), 'test-only-safe-report\n');
  });

  test('命令文件只接受单条白名单，拒绝未知内容、大文件和链接', () async {
    final root = await Directory.systemTemp.createTemp('validation-test-');
    addTearDown(() => root.delete(recursive: true));
    final files = await ValidationFiles.create(root.path);
    await files.command.writeAsString('authenticate-when-busy\n');
    expect(await files.takeCommand(), ValidationCommand.authenticateWhenBusy);
    expect(await files.command.exists(), isFalse);
    for (final value in [
      'check\nauthenticate',
      'password=test-only-password',
      'startup-on',
      'x' * 129,
    ]) {
      await files.command.writeAsString(value);
      await expectLater(files.takeCommand(), throwsA(isA<ValidationFailure>()));
      expect(await files.command.exists(), isFalse);
    }
    if (!Platform.isWindows) {
      final target = File('${root.path}/unrelated');
      await target.writeAsString('check');
      await Link(files.command.path).create(target.path);
      await expectLater(files.takeCommand(), throwsA(isA<ValidationFailure>()));
      expect(await target.readAsString(), 'check');
    }
  });

  test('消费期间原子发布的下一条命令保留到下一轮', () async {
    final root = await Directory.systemTemp.createTemp('validation-command-');
    addTearDown(() => root.delete(recursive: true));
    final files = await ValidationFiles.create(root.path);
    final command = files.command;
    final next = File('${root.path}/next-command');
    await command.writeAsString('check');
    var published = false;
    Future<void> publishNext() async {
      if (published) return;
      published = true;
      await next.writeAsString('status');
      await next.rename(command.path);
    }

    // 只在真实打开或捕获完成后发布第二条，文件读写与重命名仍由系统执行。
    final taken = await IOOverrides.runWithIOOverrides(
      files.takeCommand,
      _CommandRaceOverrides(command.path, publishNext),
    );
    expect(taken, ValidationCommand.check);
    expect(await command.exists(), isTrue);
    expect(await command.readAsString(), 'status');
    expect(await files.takeCommand(), ValidationCommand.status);
    expect(await files.directory.list().isEmpty, isTrue);
  });

  test('安全报告只序列化现有诊断白名单与固定观测字段', () {
    final report = OperationReport(
      kind: OperationKind.authenticate,
      source: OperationSource.manual,
      network: NetworkState.online,
      outcome: RecoveryOutcome.restored,
      failure: null,
      elapsed: const Duration(milliseconds: 24),
      completedAt: DateTime.utc(2026, 1, 1),
    );
    final text = ValidationOutput.encode(
      ValidationEvent.report,
      report: report,
      counters: ValidationCounters(),
      phase: RecoveryStage.verifying,
      windowVisible: true,
      trayAvailable: false,
    );
    final result = jsonDecode(text) as Map<String, dynamic>;
    expect(result['identity'], 'xduwlan-recovery-validation');
    expect(result['event'], 'report');
    expect(result['report'], {
      'time': '2026-01-01T00:00:00.000Z',
      'source': 'manual',
      'action': 'authenticate',
      'network': 'online',
      'outcome': 'restored',
      'elapsedMilliseconds': 24,
    });
    expect(result.keys.toSet(), {
      'identity',
      'event',
      'report',
      'counts',
      'phase',
      'windowVisible',
      'trayAvailable',
    });
    expect(text, isNot(contains('portal.invalid')));
  });

  test('在线手动认证不读账号且不提交，验证计数不改变生产流程', () async {
    final counts = ValidationCounters();
    final accounts = TestAccounts();
    final controller = RecoveryController(
      service: RecoveryService(
        probe: CountingProbe(TestProbe(), counts),
        portal: CountingPortal(TestPortal(), counts),
        store: CountingCredentials(accounts, counts),
      ),
      store: accounts,
    );
    addTearDown(controller.dispose);
    final report = await controller.login();
    expect(report?.outcome, RecoveryOutcome.alreadyOnline);
    expect(counts.credentialReads, 0);
    expect(counts.authenticationSubmissions, 0);
    expect(counts.probes, 1);
  });

  test('可信上下文失败时不读取凭据，安全输出不包含底层异常', () async {
    final counts = ValidationCounters();
    final accounts = TestAccounts();
    final probe = TestProbe()..state = NetworkState.portalRequired;
    final credentials = CountingCredentials(accounts, counts);
    final controller = RecoveryController(
      service: RecoveryService(
        probe: CountingProbe(probe, counts),
        portal: CountingPortal(_UnsafeFailurePortal(), counts),
        store: credentials,
      ),
      store: credentials,
    );
    addTearDown(controller.dispose);
    final report = await controller.login();
    expect(counts.credentialReads, 0);
    expect(report?.failure, FailureCode.protocol);
    final output = ValidationOutput.encode(
      ValidationEvent.report,
      counters: counts,
      report: report,
    );
    expect(output, isNot(contains('test-only-private')));
    await expectLater(
      credentials.save(const Credentials('another-user', 'another-password')),
      throwsA(isA<AppFailure>()),
    );
    expect(accounts.value?.username, 'test-user');
  });

  test('请求装饰器只计数且在失败后释放活跃计数', () async {
    final counts = ValidationCounters();
    final transport = CountingTransport(_PendingTransport(), counts);
    final scope = OperationScope();
    addTearDown(scope.finish);
    final request = transport.request(
      'GET',
      Uri.parse('https://test-only.invalid/private'),
      scope,
    );
    expect(counts.requests, 1);
    expect(counts.activeRequests, 1);
    expect(counts.maxActiveRequests, 1);
    await expectLater(request, throwsFormatException);
    expect(counts.activeRequests, 0);
    expect(jsonEncode(counts.toJson()), isNot(contains('private')));
  });

  test('忙时命令经生产串行门闩排队，手动认证不重复提交', () async {
    final harness = RuntimeHarness();
    addTearDown(harness.dispose);
    harness.probe.state = NetworkState.portalRequired;
    harness.probe.pending = Completer<NetworkState>();
    harness.portal.restoreProbe = harness.probe;
    final lines = <String>[];
    final driver = ValidationDriver(
      runtime: harness.runtime,
      counters: ValidationCounters(),
      output: lines.add,
      windowVisible: () async => harness.desktop.visible,
    );
    addTearDown(driver.dispose);
    final initialization = harness.runtime.initialize();
    await Future<void>.delayed(Duration.zero);
    await driver.dispatch(ValidationCommand.authenticateWhenBusy);
    await Future<void>.delayed(Duration.zero);
    expect(harness.recovery.manualPending, isTrue);
    expect(harness.accounts.reads, 0);
    final pending = harness.probe.pending!;
    harness.probe.pending = null;
    pending.complete(NetworkState.portalRequired);
    await initialization;
    await driver.settled();
    expect(harness.portal.calls, 1);
    expect(harness.recovery.operationSequence, 2);
    expect(harness.recovery.network, NetworkState.online);
    expect(lines.any((line) => jsonDecode(line)['event'] == 'report'), isTrue);
  });

  test('工具观测不缩短生产周期，隐藏后仍每六十秒检查', () {
    fakeAsync((time) {
      final harness = RuntimeHarness();
      final driver = ValidationDriver(
        runtime: harness.runtime,
        counters: ValidationCounters(),
        output: (_) {},
        windowVisible: () async => harness.desktop.visible,
      );
      unawaited(harness.runtime.initialize());
      time.flushMicrotasks();
      unawaited(driver.dispatch(ValidationCommand.hide));
      time.flushMicrotasks();
      expect(harness.desktop.visible, isFalse);
      time.elapse(const Duration(seconds: 59));
      expect(harness.probe.calls, 1);
      time.elapse(const Duration(seconds: 1));
      expect(harness.probe.calls, 2);
      unawaited(driver.dispatch(ValidationCommand.exit));
      time.flushMicrotasks();
      time.elapse(const Duration(minutes: 5));
      expect(harness.probe.calls, 2);
      driver.dispose();
      harness.dispose();
    });
  });

  test('操作中退出取消真实运行时作用域，迟到完成不能重新调度', () async {
    final harness = RuntimeHarness();
    addTearDown(harness.dispose);
    harness.probe.pending = Completer<NetworkState>();
    final driver = ValidationDriver(
      runtime: harness.runtime,
      counters: ValidationCounters(),
      output: (_) {},
      windowVisible: () async => harness.desktop.visible,
    );
    addTearDown(driver.dispose);
    final initialization = harness.runtime.initialize();
    await Future<void>.delayed(Duration.zero);
    await driver.dispatch(ValidationCommand.exitWhenBusy);
    await driver.settled();
    expect(harness.probe.scope!.isCancelled, isTrue);
    expect(harness.desktop.disposed, contains('exit'));
    harness.probe.pending!.complete(NetworkState.online);
    await initialization;
    expect(await harness.runtime.authenticate(OperationSource.manual), isNull);
    expect(harness.probe.calls, 1);
  });

  test('诊断读取挂起也不延迟退出的网络取消', () async {
    final harness = RuntimeHarness();
    addTearDown(harness.dispose);
    harness.probe.pending = Completer<NetworkState>();
    final diagnostics = _BlockedDiagnostics();
    final runtime = AppRuntimeController(
      recovery: harness.recovery,
      desktop: harness.desktop,
      settingsStore: harness.settings,
      diagnosticStore: diagnostics,
    );
    addTearDown(runtime.dispose);
    final driver = ValidationDriver(
      runtime: runtime,
      counters: ValidationCounters(),
      output: (_) {},
      windowVisible: () async => harness.desktop.visible,
    );
    addTearDown(driver.dispose);
    final initialization = runtime.initialize();
    await Future<void>.delayed(Duration.zero);
    final exiting = driver.dispatch(ValidationCommand.exit);
    await Future<void>.delayed(Duration.zero);
    final cancelledImmediately = harness.probe.scope!.isCancelled;
    diagnostics.pending.complete([]);
    harness.probe.pending!.complete(NetworkState.online);
    await exiting;
    await initialization;
    expect(cancelledImmediately, isTrue);
  });
}

class _UnsafeFailurePortal implements PortalClient {
  @override
  Future<PortalContext> prepare(OperationScope scope) async =>
      throw const FormatException('test-only-private-context');
  @override
  Future<void> authenticate(
    PortalContext context,
    Credentials credentials,
    OperationScope scope, {
    required Future<void> Function() beforeSubmit,
  }) async => throw const FormatException('test-only-private-authentication');
}

class _PendingTransport implements PortalTransport {
  @override
  Future<PortalResponse> request(
    String method,
    Uri url,
    OperationScope scope,
  ) async {
    await Future<void>.delayed(Duration.zero);
    throw const FormatException('test-only-private-transport');
  }
}

class _BlockedDiagnostics extends TestDiagnostics {
  final pending = Completer<List<DiagnosticRecord>>();
  @override
  Future<List<DiagnosticRecord>> load() => pending.future;
}

final class _CommandRaceOverrides extends IOOverrides {
  _CommandRaceOverrides(this.commandPath, this.publishNext);
  final String commandPath;
  final Future<void> Function() publishNext;

  @override
  File createFile(String path) {
    final file = super.createFile(path);
    return path == commandPath ? _CommandRaceFile(file, publishNext) : file;
  }
}

class _CommandRaceFile implements File {
  _CommandRaceFile(this.file, this.publishNext);
  final File file;
  final Future<void> Function() publishNext;

  @override
  String get path => file.path;

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async {
    final opened = await file.open(mode: mode);
    await publishNext();
    return opened;
  }

  @override
  Future<File> rename(String newPath) async {
    final captured = await file.rename(newPath);
    await publishNext();
    return captured;
  }

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      file.delete(recursive: recursive);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ValidationRootRaceOverrides extends IOOverrides {
  _ValidationRootRaceOverrides(this.rootPath, this.publishUnknownFiles);
  final String rootPath;
  final Future<void> Function() publishUnknownFiles;

  @override
  Directory createDirectory(String path) {
    final directory = super.createDirectory(path);
    return path == rootPath
        ? _ValidationRootRaceDirectory(directory, publishUnknownFiles)
        : directory;
  }
}

class _ValidationRootRaceDirectory implements Directory {
  _ValidationRootRaceDirectory(this.directory, this.publishUnknownFiles);
  final Directory directory;
  final Future<void> Function() publishUnknownFiles;

  @override
  String get path => directory.path;

  @override
  Future<Directory> create({bool recursive = false}) async {
    final created = await directory.create(recursive: recursive);
    await publishUnknownFiles();
    return created;
  }

  @override
  Future<Directory> createTemp([String? prefix]) =>
      directory.createTemp(prefix);

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) => directory.list(recursive: recursive, followLinks: followLinks);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
