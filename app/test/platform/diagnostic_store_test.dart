import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xduwlan_app/application/diagnostics.dart';
import 'package:xduwlan_app/core/domain.dart';

DiagnosticRecord record(int second) => DiagnosticRecord(
  time: DateTime.utc(2026, 10, 10).add(Duration(seconds: second)),
  source: OperationSource.manual,
  action: OperationKind.check,
  network: NetworkState.online,
  outcome: RecoveryOutcome.alreadyOnline,
  failure: null,
  elapsedMilliseconds: second,
);

Map<String, dynamic> validJson() => {
  'time': '2026-10-10T00:00:01.000Z',
  'source': 'manual',
  'action': 'check',
  'network': 'online',
  'outcome': 'alreadyOnline',
  'elapsedMilliseconds': 1,
};

void main() {
  late Directory directory;
  late File diagnosticFile;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('xduwlan-diagnostics-');
    diagnosticFile = File('${directory.path}/diagnostics.json');
  });
  tearDown(() => directory.delete(recursive: true));

  test('缺失文件可直接追加并由新实例读取', () async {
    final store = LocalDiagnosticStore(directory: directory);
    expect(await store.load(), isEmpty);
    await store.append(record(1));
    final loaded = await LocalDiagnosticStore(directory: directory).load();
    expect(loaded.single.time, DateTime.utc(2026, 10, 10, 0, 0, 1));
    expect(loaded.single.elapsedMilliseconds, 1);
  });

  test('操作报告只持久化允许的安全字段且不触碰凭据文件', () async {
    final credentialFile = File('${directory.path}/credentials.json');
    await credentialFile.writeAsString('fake-credential-sentinel');
    await diagnosticFile.writeAsString('[]');
    final report = OperationReport(
      kind: OperationKind.authenticate,
      source: OperationSource.automatic,
      network: NetworkState.portalRequired,
      outcome: RecoveryOutcome.failed,
      failure: FailureCode.authRejected,
      elapsed: const Duration(milliseconds: 345),
      completedAt: DateTime.utc(2026, 10, 10),
    );
    await LocalDiagnosticStore(directory: directory)
        .append(DiagnosticRecord.fromReport(report));
    expect(jsonDecode(await diagnosticFile.readAsString()), [
      {
        'time': '2026-10-10T00:00:00.000Z',
        'source': 'automatic',
        'action': 'authenticate',
        'network': 'portalRequired',
        'outcome': 'failed',
        'failure': 'authRejected',
        'elapsedMilliseconds': 345,
      },
    ]);
    expect(await credentialFile.readAsString(), 'fake-credential-sentinel');
  });

  test('乱序追加仍按时间倒序保存最新五十条', () async {
    final store = LocalDiagnosticStore(directory: directory);
    await diagnosticFile.writeAsString('[]');
    for (var second = 1; second <= 55; second++) {
      await store.append(record(second));
    }
    await store.append(record(0));
    final loaded = await store.load();
    expect(
      loaded.map((item) => item.elapsedMilliseconds),
      List.generate(50, (index) => 55 - index),
    );
    final raw = jsonDecode(await diagnosticFile.readAsString()) as List;
    expect(raw.length, 50);
    expect((raw.first as Map)['elapsedMilliseconds'], 55);
    expect((raw.last as Map)['elapsedMilliseconds'], 6);
  });

  final corruptions = <String, Object?>{
    '非列表': {'fake-private': true},
    '列表混入其他类型': [validJson(), 'fake-private'],
    '未知字段': [
      {...validJson(), 'password': 'fake-private'},
    ],
    '负耗时': [
      {...validJson(), 'elapsedMilliseconds': -1},
    ],
    '非整数耗时': [
      {...validJson(), 'elapsedMilliseconds': 1.5},
    ],
    '未知来源': [
      {...validJson(), 'source': 'fake-private'},
    ],
    '未知操作': [
      {...validJson(), 'action': 'fake-private'},
    ],
    '未知网络': [
      {...validJson(), 'network': 'fake-private'},
    ],
    '未知结果': [
      {...validJson(), 'outcome': 'fake-private'},
    ],
    '未知失败类别': [
      {...validJson(), 'failure': 'fake-private'},
    ],
    '无效时间': [
      {...validJson(), 'time': '2026-99-99T00:00:01.000Z'},
    ],
    '缺失必要字段': [
      Map<String, dynamic>.from(validJson())..remove('elapsedMilliseconds'),
    ],
    '超量记录': List.generate(51, (_) => validJson()),
  };
  for (final corruption in corruptions.entries) {
    test('损坏诊断完整隔离后从空记录继续：${corruption.key}', () async {
      final raw = jsonEncode(corruption.value);
      await diagnosticFile.writeAsString(raw);
      final store = LocalDiagnosticStore(directory: directory);
      expect(await store.load(), isEmpty);
      expect(await diagnosticFile.exists(), isFalse);
      expect(await File('${diagnosticFile.path}.corrupt').exists(), isTrue);
      expect(await File('${diagnosticFile.path}.corrupt').readAsString(), raw);
      await store.append(record(2));
      expect((await store.load()).single.elapsedMilliseconds, 2);
    });
  }

  test('非 JSON 原文及超大文件均被隔离且只保留一个隔离文件', () async {
    final store = LocalDiagnosticStore(directory: directory);
    await diagnosticFile.writeAsString('fake-private-invalid-json');
    expect(await store.load(), isEmpty);
    await diagnosticFile.writeAsString('${' ' * (128 * 1024)}[]');
    expect(await store.load(), isEmpty);
    final files = await directory.list().toList();
    expect(files.map((file) => file.path), ['${diagnosticFile.path}.corrupt']);
  });

  test('负耗时记录在写入前被拒绝且已有记录保留', () async {
    final initial = jsonEncode([validJson()]);
    await diagnosticFile.writeAsString(initial);
    final invalid = DiagnosticRecord(
      time: DateTime.utc(2026, 10, 10),
      source: OperationSource.manual,
      action: OperationKind.check,
      network: NetworkState.online,
      outcome: null,
      failure: null,
      elapsedMilliseconds: -1,
    );
    await expectLater(
      LocalDiagnosticStore(directory: directory).append(invalid),
      throwsA(isA<Exception>()),
    );
    expect(await diagnosticFile.readAsString(), initial);
  });

  test('报告的负微秒耗时不能在转换时截断为零', () {
    final report = OperationReport(
      kind: OperationKind.check,
      source: OperationSource.manual,
      network: NetworkState.unknown,
      outcome: null,
      failure: null,
      elapsed: const Duration(microseconds: -1),
      completedAt: DateTime.utc(2026, 10, 10),
    );
    expect(
      () => DiagnosticRecord.fromReport(report),
      throwsA(isA<FormatException>().having((e) => e.source, 'source', isNull)),
    );
  });

  test('并发追加包含同路径不同实例时不丢记录', () async {
    await diagnosticFile.writeAsString('[]');
    final stores = [
      LocalDiagnosticStore(directory: directory),
      LocalDiagnosticStore(file: diagnosticFile),
    ];
    await Future.wait([
      for (var second = 1; second <= 30; second++)
        stores[second % 2].append(record(second)),
    ]);
    final loaded = await stores.first.load();
    expect(
      loaded.map((item) => item.elapsedMilliseconds),
      List.generate(30, (index) => 30 - index),
    );
    expect(await File('${diagnosticFile.path}.tmp').exists(), isFalse);
  });

  test('并发追加和清空保持调用顺序', () async {
    await diagnosticFile.writeAsString('[]');
    final store = LocalDiagnosticStore(directory: directory);
    await Future.wait([
      store.append(record(1)),
      store.clear(),
      store.append(record(2)),
    ]);
    expect((await store.load()).map((item) => item.elapsedMilliseconds), [2]);
  });

  test('写入失败保留原文件，后续操作仍可成功', () async {
    final initial = jsonEncode([validJson()]);
    await diagnosticFile.writeAsString(initial);
    final blockedTemporary = Directory('${diagnosticFile.path}.tmp');
    await blockedTemporary.create();
    final store = LocalDiagnosticStore(directory: directory);
    await expectLater(
      store.append(record(2)),
      throwsA(
        isA<FileSystemException>().having(
          (error) => error.toString(),
          'message',
          isNot(contains(directory.path)),
        ),
      ),
    );
    expect(await diagnosticFile.readAsString(), initial);
    await blockedTemporary.delete();
    await store.append(record(2));
    expect((await store.load()).map((item) => item.elapsedMilliseconds), [
      2,
      1,
    ]);
  });

  test('无法读取或写入的路径仅产生安全文件错误', () async {
    final store = LocalDiagnosticStore(file: File(directory.path));
    final safeError = isA<FileSystemException>().having(
      (error) => error.toString(),
      'message',
      isNot(contains(directory.path)),
    );
    await expectLater(store.load(), throwsA(safeError));
    await expectLater(store.append(record(1)), throwsA(safeError));
  });

  test('清空同时删除当前记录与隔离记录并可重复执行', () async {
    await diagnosticFile.writeAsString(jsonEncode([validJson()]));
    await File('${diagnosticFile.path}.corrupt').writeAsString('fake-private');
    final store = LocalDiagnosticStore(directory: directory);
    await store.clear();
    await store.clear();
    expect(await directory.list().toList(), isEmpty);
    await store.append(record(1));
    expect((await store.load()).single.elapsedMilliseconds, 1);
  });
}
