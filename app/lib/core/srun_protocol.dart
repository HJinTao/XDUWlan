import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'domain.dart';

const _portalAlphabet =
    'LVoJPiCN2R8G90yg+hmFHuacZ1OWMnrsSTXkYpUq/3dlbfKwv6xztjI7DeBE45QA';
const _standardAlphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const _mask = 0xffffffff;

/// 按已观察的字段顺序与 JavaScript UTF-16 位运算构造一次登录参数。
Map<String, Object> buildLoginParams(
  Credentials credentials,
  PortalContext context,
  String challenge,
  String callback,
  int timestamp,
) {
  _requireUnicode(credentials.username);
  _requireUnicode(credentials.password);
  final hmd5 = Hmac(
    md5,
    utf8.encode(challenge),
  ).convert(utf8.encode(credentials.password)).toString();
  final plain = jsonEncode({
    'username': credentials.username,
    'password': credentials.password,
    'ip': context.ip,
    'acid': context.acid,
    'enc_ver': 'srun_bx1',
  });
  final encoded = base64Encode(_xencode(plain, challenge));
  final info =
      '{SRBX1}${String.fromCharCodes(encoded.codeUnits.map((unit) {
        final index = _standardAlphabet.indexOf(String.fromCharCode(unit));
        return index < 0 ? unit : _portalAlphabet.codeUnitAt(index);
      }))}';
  final checksum = sha1
      .convert(
        utf8.encode(
          [
            credentials.username,
            hmd5,
            context.acid,
            context.ip,
            '200',
            '1',
            info,
          ].map((value) => challenge + value).join(),
        ),
      )
      .toString();
  return {
    'callback': callback,
    'action': 'login',
    'username': credentials.username,
    'password': '{MD5}$hmd5',
    'os': 'Dart',
    'name': 'XDUWlan',
    'double_stack': 0,
    'chksum': checksum,
    'info': info,
    'ac_id': context.acid,
    'ip': context.ip,
    'n': '200',
    'type': '1',
    '_': timestamp,
  };
}

/// 只解析匹配回调的严格 JSON 对象，绝不执行 JavaScript。
Map<String, dynamic> parseJsonp(String text, String callback) {
  final match = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').firstMatch(callback);
  if (match == null || match.end != callback.length) {
    throw const AppFailure(FailureCode.protocol);
  }
  var body = text.trim();
  if (body.endsWith(';')) body = body.substring(0, body.length - 1);
  final prefix = '$callback(';
  if (!body.startsWith(prefix) || !body.endsWith(')')) {
    throw const AppFailure(FailureCode.protocol);
  }
  try {
    final value = jsonDecode(body.substring(prefix.length, body.length - 1));
    if (value is Map<String, dynamic>) return value;
  } on FormatException {
    throw const AppFailure(FailureCode.protocol);
  } on StackOverflowError {
    throw const AppFailure(FailureCode.protocol);
  }
  throw const AppFailure(FailureCode.protocol);
}

void _requireUnicode(String value) {
  final units = value.codeUnits;
  for (var index = 0; index < units.length; index++) {
    final unit = units[index];
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++index >= units.length ||
          units[index] < 0xdc00 ||
          units[index] > 0xdfff) {
        throw const AppFailure(FailureCode.credentialsInvalid);
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw const AppFailure(FailureCode.credentialsInvalid);
    }
  }
}

List<int> _packWords(String value, {required bool includeLength}) {
  final units = value.codeUnits;
  final words = <int>[];
  for (var start = 0; start < units.length; start += 4) {
    var word = 0;
    for (
      var offset = 0;
      offset < 4 && start + offset < units.length;
      offset++
    ) {
      word |= units[start + offset] << (8 * offset);
    }
    words.add(word & _mask);
  }
  if (includeLength) words.add(units.length);
  return words;
}

Uint8List _xencode(String message, String key) {
  if (message.isEmpty) return Uint8List(0);
  final words = _packWords(message, includeLength: true);
  final keys = _packWords(key, includeLength: false);
  while (keys.length < 4) {
    keys.add(0);
  }
  var z = words.last;
  var sum = 0;
  for (var round = 0; round < 6 + 52 ~/ words.length; round++) {
    sum = (sum + 0x9e3779b9) & _mask;
    final e = (sum >> 2) & 3;
    for (var position = 0; position < words.length; position++) {
      final y = words[(position + 1) % words.length];
      var mix = (z >> 5) ^ ((y << 2) & _mask);
      mix += (y >> 3) ^ ((z << 4) & _mask) ^ sum ^ y;
      mix += keys[(position & 3) ^ e] ^ z;
      z = words[position] = (words[position] + mix) & _mask;
    }
  }
  final bytes = ByteData(words.length * 4);
  for (var index = 0; index < words.length; index++) {
    bytes.setUint32(index * 4, words[index], Endian.little);
  }
  return bytes.buffer.asUint8List();
}
