import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xduwlan_app/tool/thinkpad_lab.dart';

void main() {
  test('只接受固定动作、批次标识和安全目录参数', () {
    expect(ThinkPadLabOptions.parse(['--action=status']), isNotNull);
    expect(
      ThinkPadLabOptions.parse([
        '--action=observe',
        '--duration-seconds=30',
        '--batch-id=ios-lab-01',
        '--evidence-directory=/tmp/xduwlan-lab-test',
      ]),
      isNotNull,
    );
    for (final args in [
      ['--action=sh'],
      ['--action=status', '--connection=other'],
      ['--action=status', '--command=nmcli connection down xduwlan-lab-b'],
      ['--action=status', '--password=test-only-password'],
      ['--action=status', '--batch-id=contains space'],
      ['--action=observe', '--duration-seconds=0'],
      ['--action=status', '--evidence-directory=relative'],
    ]) {
      expect(() => ThinkPadLabOptions.parse(args), throwsFormatException);
    }
  });

  test('命令只能使用固定 NetworkManager 连接且结果脱敏', () async {
    final calls = <List<String>>[];
    final runner = FakeProcessRunner((executable, arguments) {
      calls.add([executable, ...arguments]);
      return const ProcessResultData(exitCode: 0, stdout: 'xduwlan-lab-b\n');
    });
    final lab = ThinkPadLab(
      runner: runner,
      platformIsLinux: true,
      hostLink: () async => HostLinkCategory.wired,
    );

    final status = await lab.run(
      const ThinkPadLabOptions(action: ThinkPadLabAction.status),
    );
    expect(status.resultCategory, ThinkPadResultCategory.ready);
    expect(calls.single, ['nmcli', '-t', '-f', 'NAME', 'connection', 'show']);

    final down = await lab.run(
      const ThinkPadLabOptions(action: ThinkPadLabAction.down),
    );
    expect(down.resultCategory, ThinkPadResultCategory.completed);
    expect(calls.last, [
      'nmcli',
      'connection',
      'down',
      'id',
      ThinkPadLab.fixedConnection,
    ]);
    expect(jsonDecode(down.toJson())['connection'], isNull);
    expect(down.toJson(), isNot(contains('test-only-password')));
  });

  test('证据只能写入空的私有目录并拒绝目录外路径', () async {
    final parent = await Directory.systemTemp.createTemp('thinkpad-lab-');
    addTearDown(() => parent.delete(recursive: true));
    final evidence = Directory('${parent.path}/evidence');
    final lab = ThinkPadLab(
      runner: FakeProcessRunner(
        (executable, arguments) => const ProcessResultData(exitCode: 0),
      ),
      platformIsLinux: true,
      hostLink: () async => HostLinkCategory.wired,
    );
    final options = ThinkPadLabOptions(
      action: ThinkPadLabAction.status,
      evidenceDirectory: evidence.path,
      batchId: 'redacted-01',
    );
    await lab.run(options);
    expect(await File('${evidence.path}/thinkpad-lab.jsonl').exists(), isTrue);
    expect(() => lab.run(options), throwsA(isA<ThinkPadLabFailure>()));
    final existing = Directory('${parent.path}/existing')..createSync();
    File('${existing.path}/secret').writeAsStringSync('sentinel');
    await expectLater(
      lab.run(
        ThinkPadLabOptions(
          action: ThinkPadLabAction.status,
          evidenceDirectory: existing.path,
        ),
      ),
      throwsA(isA<ThinkPadLabFailure>()),
    );
    expect(File('${existing.path}/secret').readAsStringSync(), 'sentinel');
  });
}

typedef FakeProcessHandler = ProcessResultData Function(
  String executable,
  List<String> arguments,
);

class FakeProcessRunner implements ThinkPadProcessRunner {
  FakeProcessRunner(this.handler);
  final FakeProcessHandler handler;
  @override
  Future<ProcessResultData> run(
    String executable,
    List<String> arguments,
  ) async => handler(executable, arguments);
}
