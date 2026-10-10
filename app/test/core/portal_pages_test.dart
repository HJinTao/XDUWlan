import 'package:flutter_test/flutter_test.dart';
import 'package:xduwlan_app/core/domain.dart';
import 'package:xduwlan_app/core/portal_pages.dart';

void main() {
  final portal = Uri.parse('https://portal.example.test');
  final entry = Uri.parse('http://probe.example.test/generate_204');
  final protocolFailure = throwsA(
    isA<AppFailure>().having((e) => e.code, 'code', FailureCode.protocol),
  );

  test('唯一空 POST 入口提升为可信 HTTPS', () {
    final nav = findPortalNavigation(
      '<FORM METHOD="post" ACTION="http://portal.example.test/index_8.html"></FORM>',
      entry,
      portal,
    );
    expect(nav?.method, 'POST');
    expect(nav?.uri, Uri.parse('https://portal.example.test/index_8.html'));
    expect(nav.toString(), isNot(contains('portal.example.test')));
  });

  test('meta refresh 相对导航与 HTML 实体正确解析', () {
    final nav = findPortalNavigation(
      '<meta content="0; URL=/srun_portal_pc?ac_id=8&amp;theme=test" http-equiv="Refresh">',
      Uri.parse('https://portal.example.test/index_8.html'),
      portal,
    );
    expect(nav?.method, 'GET');
    expect(
      nav?.uri,
      Uri.parse(
        'https://portal.example.test/srun_portal_pc?ac_id=8&theme=test',
      ),
    );
  });

  test('完整 HTML 文档中的唯一导航可识别', () {
    final nav = findPortalNavigation(
      '<!doctype html><html><head><meta http-equiv="refresh" content="0;url=https://portal.example.test/srun_portal_pc"></head><body></body></html>',
      entry,
      portal,
    );
    expect(nav?.uri, Uri.parse('https://portal.example.test/srun_portal_pc'));
  });

  for (final target in [
    'https://portal.example.test.attacker.test/',
    'https://attacker.test/?next=portal.example.test',
    'https://user:secret@portal.example.test/',
    'https://portal.example.test:8443/',
    'http://portal.example.test:443/',
    'javascript:alert(1)',
    'https://[invalid',
    '//attacker.test/',
    'https://portal.example.test/#fragment',
    'https://portal.example.test/\\attacker',
    ' https://portal.example.test/',
    'https://portal.example.test/path%0a',
  ]) {
    test('导航拒绝不可信目标 ${target.hashCode}', () {
      expect(() => trustedPortalUri(target, entry, portal), protocolFailure);
    });
  }

  for (final uri in [
    'http://portal.example.test',
    'https://portal.example.test:8443',
    'https://user:secret@portal.example.test',
    'https://portal.example.test?token=secret',
    'https://portal.example.test#fragment',
    'https://portal.example.test/path%0a',
  ]) {
    test('拒绝不合规 Portal 配置 ${uri.hashCode}', () {
      expect(
        () => trustedPortalUri('/', entry, Uri.parse(uri)),
        protocolFailure,
      );
    });
  }

  for (final body in [
    '<form method="post" action="https://portal.example.test/"><input name="password"></form>',
    '<form method="post" action="https://portal.example.test/"><textarea></textarea></form>',
    '<form method="get" action="https://portal.example.test/"></form>',
    '<form method="post" action="https://portal.example.test/"></form><form></form>',
    '<form method="post" action="https://portal.example.test/" action="https://attacker.test/"></form>',
    '<form METHOD="post" method="get" action="https://portal.example.test/"></form>',
    '<form method="post" action="https://portal.example.test/"><form></form></form>',
    '<meta http-equiv="refresh" content="0;url=https://portal.example.test/"><form method="post" action="https://portal.example.test/"></form>',
    '<meta http-equiv="refresh" content="0;url=https://portal.example.test/"><meta http-equiv="refresh" content="0;url=https://portal.example.test/">',
    '<script>var fake = \'<form method="post" action="https://portal.example.test/"></form>\';</script>',
  ]) {
    test('非空或歧义页面不重放 ${body.hashCode}', () {
      expect(findPortalNavigation(body, entry, portal), isNull);
    });
  }

  test('可信上下文只解析字符串 IPv4 与 acid，不执行脚本', () {
    final context = parsePortalContext(
      '<script>var CONFIG = {ip: "192.0.2.10", acid: "8", note: "} quote"}; throw new Error("not executed");</script>',
      portal,
    );
    expect(context.origin, portal);
    expect(context.ip, '192.0.2.10');
    expect(context.acid, '8');
  });

  test('只解析实际 script 中的声明不受正文引号影响', () {
    final context = parsePortalContext(
      '<html><body>Today\'s portal<script>var CONFIG={ip:"192.0.2.10",acid:"8"};</script></body></html>',
      portal,
    );
    expect(context.ip, '192.0.2.10');
  });

  for (final body in [
    '<script>var fake = \'var CONFIG={ip:"192.0.2.10",acid:"8"};\';</script>',
    '<script>// var CONFIG={ip:"192.0.2.10",acid:"8"};\nvar harmless=1;</script>',
    '<div>var CONFIG={ip:"192.0.2.10",acid:"8"};</div><script>var harmless=1;</script>',
  ]) {
    test('脚本字符串注释或正文不能冒充 CONFIG ${body.hashCode}', () {
      expect(() => parsePortalContext(body, portal), protocolFailure);
    });
  }

  for (final body in [
    'var CONFIG={ip:"not-an-ip",acid:"8"};',
    'var CONFIG={ip:"192.0.2.10",acid:"0"};',
    'var CONFIG={ip:"192.0.2.10"};',
    'var CONFIG={ip:"2001:db8::1",acid:"8"};',
    'var CONFIG={ip:"192.0.2.10",acid:"8",ip:"192.0.2.11"};',
    'var CONFIG={ip:"192.0.2.10",acid:"8",ip:123};',
    'var CONFIG={ip:"192.000.2.10",acid:"8"};',
    'var CONFIG={ip:"256.0.2.10",acid:"8"};',
    'var CONFIG={ip:"192.0.2.10",acid:"0008"};',
    'var CONFIG={ip:"192.0.2.10",acid:"12345678901"};',
    'var CONFIG={note:{ip:"192.0.2.10",acid:"8"}};',
    'var CONFIG={note:"ip:\\"192.0.2.10\\",acid:\\"8\\""};',
    'var CONFIG={ip:"192.0.2.10",acid:"8"};var CONFIG={ip:"192.0.2.11",acid:"8"};',
    'var CONFIG={ip:"192.0.2.10",acid:"8"',
  ]) {
    test('缺失非法或歧义上下文安全失败 ${body.hashCode}', () {
      expect(() => parsePortalContext(body, portal), protocolFailure);
    });
  }
}
