import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xduwlan_app/core/domain.dart';
import 'package:xduwlan_app/core/srun_protocol.dart';

void main() {
  final vectors = jsonDecode(
    File('test/fixtures/srun_vectors.json').readAsStringSync(encoding: utf8),
  ) as List<dynamic>;
  for (var index = 0; index < vectors.length; index++) {
    final vector = vectors[index] as Map<String, dynamic>;
    test('编码与独立 JavaScript 虚构向量 $index 逐字节一致', () {
      final params = buildLoginParams(
        Credentials(vector['username'] as String, vector['password'] as String),
        PortalContext(
          Uri.parse('https://portal.example.test'),
          vector['ip'] as String,
          vector['acid'] as String,
        ),
        vector['challenge'] as String,
        'xduwlan_cb',
        1234,
      );
      expect(params['password'], '{MD5}${vector['hmd5']}');
      expect(params['info'], vector['info']);
      expect(params['chksum'], vector['checksum']);
      expect(params.keys.toList(), [
        'callback',
        'action',
        'username',
        'password',
        'os',
        'name',
        'double_stack',
        'chksum',
        'info',
        'ac_id',
        'ip',
        'n',
        'type',
        '_',
      ]);
      expect(params['os'], 'Dart');
      expect(params['n'], '200');
      expect(params['type'], '1');
    });
  }

  test('独立 JavaScript 扩展向量覆盖引号反斜线控制字符与 emoji', () {
    final params = buildLoginParams(
      const Credentials('quote"slash\\user', 'line\n\tcontrol\u0001-😀'),
      PortalContext(
        Uri.parse('https://portal.example.test'),
        '192.0.2.10',
        '8',
      ),
      '0123456789abcdef0123456789abcdef',
      'xduwlan_cb',
      1234,
    );
    expect(params['password'], '{MD5}f8c24aa90d386964de2b41ab55aeb02a');
    expect(
      params['info'],
      '{SRBX1}dno0xU+lRKC17aDAgJEMDOgmc/dnfhkaafYLdU/Unu97LxSxpx+6R3dwOs/Jk/EvuFdYZN+aevQZc6tAcp054TuOaSm7/jZ/ZhsQllPmx10HgU7jv90H2Z8qj7iUp2tB6t3bIwRBWUElMGxilY4tWeeVMHYjdfTSUNEYvWr8S/t=',
    );
    expect(params['chksum'], '28c59d7acaceaca436a9fdfc0962c5c4a6014d3c');
  });

  for (final input in [
    Credentials(String.fromCharCode(0xd800), 'fictional-password'),
    Credentials('fictional-user', String.fromCharCode(0xdc00)),
  ]) {
    test('非法 Unicode 不静默替换为另一组认证输入 ${input.hashCode}', () {
      expect(
        () => buildLoginParams(
          input,
          PortalContext(
            Uri.parse('https://portal.example.test'),
            '192.0.2.10',
            '8',
          ),
          'fictional-token',
          'xduwlan_cb',
          1234,
        ),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.code,
            'code',
            FailureCode.credentialsInvalid,
          ),
        ),
      );
    });
  }

  test('JSONP 仅接受匹配回调的严格对象', () {
    expect(parseJsonp('  xduwlan_cb({"error":"ok"});  ', 'xduwlan_cb'), {
      'error': 'ok',
    });
  });
  for (final text in [
    'wrong({"error":"ok"})',
    'xduwlan_cb([])',
    'xduwlan_cb(null)',
    'xduwlan_cb({broken})',
    'xduwlan_cb({});alert(1)',
    'xduwlan_cb({"challenge":NaN})',
    'xduwlan_cb({"challenge":Infinity})',
    'xduwlan_cb({});;',
  ]) {
    test('JSONP 拒绝畸形响应 ${text.hashCode}', () {
      expect(
        () => parseJsonp(text, 'xduwlan_cb'),
        throwsA(
          isA<AppFailure>().having((e) => e.code, 'code', FailureCode.protocol),
        ),
      );
    });
  }
  for (final callback in ['cb);alert(1)//', '中文', '1callback', '']) {
    test('JSONP 拒绝非法回调 ${callback.hashCode}', () {
      expect(
        () => parseJsonp('$callback({})', callback),
        throwsA(isA<AppFailure>()),
      );
    });
  }
}
