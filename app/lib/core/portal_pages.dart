import 'package:html/parser.dart' show HtmlParser;

import 'domain.dart';

class PortalNavigation {
  const PortalNavigation(this.method, this.uri);
  final String method;
  final Uri uri;
  @override
  String toString() => 'PortalNavigation($method, <redacted>)';
}

/// 精确校验可信主机与默认端口，将可信 HTTP 导航提升为 HTTPS。
Uri trustedPortalUri(String target, Uri base, Uri portal) {
  try {
    final forbidden = RegExp(r'[\s\\\x00-\x20\x7f]');
    if (forbidden.hasMatch(target) ||
        forbidden.hasMatch(Uri.decodeFull(target)) ||
        forbidden.hasMatch(portal.toString()) ||
        forbidden.hasMatch(Uri.decodeFull(portal.toString())) ||
        portal.scheme != 'https' ||
        portal.host.isEmpty ||
        portal.port != 443 ||
        portal.userInfo.isNotEmpty ||
        portal.authority.contains('@') ||
        portal.hasQuery ||
        portal.hasFragment) {
      throw const AppFailure(FailureCode.protocol);
    }
    final parsed = base.resolve(target);
    if (!['http', 'https'].contains(parsed.scheme) ||
        parsed.host != portal.host ||
        parsed.userInfo.isNotEmpty ||
        parsed.authority.contains('@') ||
        parsed.hasFragment ||
        parsed.port != (parsed.scheme == 'http' ? 80 : 443)) {
      throw const AppFailure(FailureCode.protocol);
    }
    return parsed.replace(
      scheme: 'https',
      host: portal.host,
      port: 443,
      path: parsed.path.isEmpty ? '/' : parsed.path,
    );
  } on FormatException {
    throw const AppFailure(FailureCode.protocol);
  } on ArgumentError {
    throw const AppFailure(FailureCode.protocol);
  }
}

/// 只重放唯一空 POST 或 meta refresh；不执行脚本或修复歧义页面。
PortalNavigation? findPortalNavigation(String body, Uri base, Uri portal) {
  final parser = HtmlParser(body);
  final document = parser.parse();
  // HTML 树会折叠重复属性及嵌套 form，必须同时检查原始解析错误。
  if (parser.errors.any(
    (error) => !{
      'expected-doctype-but-got-start-tag',
      'expected-doctype-but-got-chars',
      'expected-doctype-but-got-eof',
    }.contains(error.errorCode),
  )) {
    return null;
  }
  final forms = document.querySelectorAll('form');
  final controls = document.querySelectorAll('input, textarea, select, button');
  final candidates = <(String, String)>[];
  for (final meta in document.querySelectorAll('meta')) {
    if ((meta.attributes['http-equiv'] ?? '').toLowerCase() != 'refresh') {
      continue;
    }
    final content = meta.attributes['content'] ?? '';
    final match = RegExp(
      r'^\s*\d+(?:\.\d+)?\s*;\s*url\s*=\s*(.+?)\s*$',
      caseSensitive: false,
    ).firstMatch(content);
    if (match == null || match.end != content.length) return null;
    var target = match.group(1)!;
    if ((target.startsWith('"') && target.endsWith('"')) ||
        (target.startsWith("'") && target.endsWith("'"))) {
      target = target.substring(1, target.length - 1);
    }
    candidates.add(('GET', target));
  }
  if (forms.length == 1 && controls.isEmpty) {
    final form = forms.single;
    final action = form.attributes['action'];
    if ((form.attributes['method'] ?? '').toLowerCase() == 'post' &&
        action != null &&
        action.isNotEmpty) {
      candidates.add(('POST', action));
    }
  }
  if (candidates.length != 1) return null;
  final (method, target) = candidates.single;
  return PortalNavigation(method, trustedPortalUri(target, base, portal));
}

/// 只提取已观察的直接字符串字段；不把脚本当作可执行代码。
PortalContext parsePortalContext(String body, Uri portal) {
  final origin = trustedPortalUri('/', portal, portal).replace(path: '');
  final block = _configBlock(body);
  final fields = _objectFields(block);
  final ip = _plainString(fields['ip']);
  final acid = _plainString(fields['acid']);
  final parts = ip.split('.');
  if (parts.length != 4 ||
      parts.any((part) {
        final match = RegExp(r'^(?:0|[1-9][0-9]{0,2})$').firstMatch(part);
        return match == null ||
            match.end != part.length ||
            int.parse(part) > 255;
      })) {
    throw const AppFailure(FailureCode.protocol);
  }
  final acidMatch = RegExp(r'^[1-9][0-9]{0,9}$').firstMatch(acid);
  if (acidMatch == null || acidMatch.end != acid.length) {
    throw const AppFailure(FailureCode.protocol);
  }
  return PortalContext(origin, ip, acid);
}

String _configBlock(String body) {
  if (RegExp(r'<\s*(?:!|/?[A-Za-z])').hasMatch(body)) {
    // 仅观察实际内联脚本，不让页面正文和 HTML 属性冒充配置声明。
    body = HtmlParser(body)
        .parse()
        .querySelectorAll('script')
        .map((script) => script.text)
        .join('\n');
  }
  final declaration = RegExp(r'\b(?:var|let|const)\s+CONFIG\s*=\s*\{');
  final starts = <int>[];
  var cursor = 0;
  while (cursor < body.length) {
    final skipped = _skipComment(body, cursor);
    if (skipped != cursor) {
      cursor = skipped;
      continue;
    }
    if (body[cursor] == '"' || body[cursor] == "'" || body[cursor] == '`') {
      cursor = _stringEnd(body, cursor);
      continue;
    }
    final match = declaration.matchAsPrefix(body, cursor);
    if (match != null) {
      starts.add(match.end - 1);
      cursor = match.end;
    } else {
      cursor++;
    }
  }
  if (starts.length != 1) throw const AppFailure(FailureCode.protocol);
  final start = starts.single;
  var depth = 0;
  cursor = start;
  while (cursor < body.length) {
    final skipped = _skipComment(body, cursor);
    if (skipped != cursor) {
      cursor = skipped;
      continue;
    }
    final char = body[cursor];
    if (char == '"' || char == "'" || char == '`') {
      cursor = _stringEnd(body, cursor);
      continue;
    }
    if (char == '{') depth++;
    if (char == '}' && --depth == 0) return body.substring(start, cursor + 1);
    cursor++;
  }
  throw const AppFailure(FailureCode.protocol);
}

Map<String, String> _objectFields(String block) {
  final fields = <String, String>{};
  var cursor = 1;
  while (true) {
    cursor = _skipSpace(block, cursor);
    if (cursor == block.length - 1) return fields;
    if (cursor >= block.length) throw const AppFailure(FailureCode.protocol);
    String key;
    if (block[cursor] == '"' || block[cursor] == "'") {
      final end = _stringEnd(block, cursor);
      key = _plainString(block.substring(cursor, end));
      cursor = end;
    } else {
      final match = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*')
          .matchAsPrefix(block, cursor);
      if (match == null) throw const AppFailure(FailureCode.protocol);
      key = match.group(0)!;
      cursor = match.end;
    }
    cursor = _skipSpace(block, cursor);
    if (cursor >= block.length ||
        block[cursor] != ':' ||
        fields.containsKey(key)) {
      throw const AppFailure(FailureCode.protocol);
    }
    cursor = _skipSpace(block, cursor + 1);
    final start = cursor;
    final brackets = <String>[];
    while (cursor < block.length - 1) {
      final skipped = _skipComment(block, cursor);
      if (skipped != cursor) {
        cursor = skipped;
        continue;
      }
      final char = block[cursor];
      if (char == '"' || char == "'" || char == '`') {
        cursor = _stringEnd(block, cursor);
        continue;
      }
      if (char == ',' && brackets.isEmpty) break;
      if ('{[('.contains(char)) {
        brackets.add(char);
      } else if ('}])'.contains(char)) {
        if (brackets.isEmpty ||
            '{[('.indexOf(brackets.removeLast()) != '}])'.indexOf(char)) {
          throw const AppFailure(FailureCode.protocol);
        }
      }
      cursor++;
    }
    if (brackets.isNotEmpty || cursor <= start) {
      throw const AppFailure(FailureCode.protocol);
    }
    fields[key] = block.substring(start, cursor).trim();
    if (cursor == block.length - 1) return fields;
    cursor++;
  }
}

String _plainString(String? value) {
  if (value == null ||
      value.length < 2 ||
      !['"', "'"].contains(value[0]) ||
      value[value.length - 1] != value[0] ||
      value.contains('\\') ||
      _stringEnd(value, 0) != value.length) {
    throw const AppFailure(FailureCode.protocol);
  }
  return value.substring(1, value.length - 1);
}

int _stringEnd(String value, int start) {
  final quote = value[start];
  for (var cursor = start + 1; cursor < value.length; cursor++) {
    if (value[cursor] == '\\') {
      cursor++;
    } else if (value[cursor] == quote) {
      return cursor + 1;
    }
  }
  throw const AppFailure(FailureCode.protocol);
}

int _skipComment(String value, int cursor) {
  if (value.startsWith('//', cursor)) {
    final end = value.indexOf('\n', cursor + 2);
    return end < 0 ? value.length : end + 1;
  }
  if (value.startsWith('/*', cursor)) {
    final end = value.indexOf('*/', cursor + 2);
    if (end < 0) throw const AppFailure(FailureCode.protocol);
    return end + 2;
  }
  return cursor;
}

int _skipSpace(String value, int cursor) {
  while (cursor < value.length) {
    if (value[cursor].trim().isEmpty) {
      cursor++;
      continue;
    }
    final skipped = _skipComment(value, cursor);
    if (skipped == cursor) break;
    cursor = skipped;
  }
  return cursor;
}
