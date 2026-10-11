import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

const _bundleIdentifier = 'cn.xduwlan.desktop';

Future<void> excludeFromBackup(File file) async {
  if (!Platform.isIOS) return;
  await const MethodChannel('cn.xduwlan/storage')
      .invokeMethod<void>('excludeFromBackup', file.path);
}

/// 延迟请求平台目录；macOS 解除沙盒后继续使用已有容器中的支持目录。
/// 注入的目录和平台标志用于离线验证，不读取或迁移目录内的文件。
Future<Directory> resolveApplicationSupportDirectory({
  Directory? supportDirectory,
  bool? macOS,
}) async {
  final support = supportDirectory ?? await getApplicationSupportDirectory();
  if (!(macOS ?? Platform.isMacOS)) return support;

  final normalized = Directory.fromUri(support.absolute.uri.normalizePath());
  final segments = normalized.uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (!_endsWith(segments, [
        'Library',
        'Application Support',
        _bundleIdentifier,
      ]) ||
      _endsWith(segments, [
        'Library',
        'Containers',
        _bundleIdentifier,
        'Data',
        'Library',
        'Application Support',
        _bundleIdentifier,
      ])) {
    return support;
  }

  // 只从已确认的常规支持目录推导根目录，不查询用户环境变量。
  final root = normalized.parent.parent.parent;
  final legacy = Directory(
    '${root.path}/Library/Containers/$_bundleIdentifier/Data/'
    'Library/Application Support/$_bundleIdentifier',
  );
  return await legacy.exists() ? legacy : support;
}

bool _endsWith(List<String> segments, List<String> suffix) {
  if (segments.length < suffix.length) return false;
  final offset = segments.length - suffix.length;
  for (var index = 0; index < suffix.length; index++) {
    if (segments[offset + index] != suffix[index]) return false;
  }
  return true;
}
