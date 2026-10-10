import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../platform/application_support.dart';

class AppSettings {
  const AppSettings({
    this.automaticRecoveryEnabled = true,
    this.launchAtStartup = false,
  });

  final bool automaticRecoveryEnabled;
  final bool launchAtStartup;

  AppSettings copyWith({
    bool? automaticRecoveryEnabled,
    bool? launchAtStartup,
  }) => AppSettings(
    automaticRecoveryEnabled:
        automaticRecoveryEnabled ?? this.automaticRecoveryEnabled,
    launchAtStartup: launchAtStartup ?? this.launchAtStartup,
  );

  Map<String, dynamic> toJson() => {
    'automaticRecoveryEnabled': automaticRecoveryEnabled,
    'launchAtStartup': launchAtStartup,
  };

  static AppSettings fromJson(Object? raw) {
    if (raw is! Map<String, dynamic> || raw.length != 2) {
      throw const FormatException('本地设置不可用');
    }
    final automatic = raw['automaticRecoveryEnabled'];
    final startup = raw['launchAtStartup'];
    if (automatic is! bool || startup is! bool) {
      throw const FormatException('本地设置不可用');
    }
    return AppSettings(
      automaticRecoveryEnabled: automatic,
      launchAtStartup: startup,
    );
  }
}

abstract interface class SettingsStore {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}

class LocalSettingsStore implements SettingsStore {
  LocalSettingsStore({this.directory, this.file});
  final Directory? directory;
  final File? file;
  static const fileName = 'settings.json';
  static const _maxBytes = 4096;
  static final Map<String, Future<void>> _pending = {};

  Future<File> _resolveFile() async {
    if (file case final configured?) return configured;
    final root = directory ?? await resolveApplicationSupportDirectory();
    return File('${root.path}/$fileName');
  }

  /// 同一路径的读写共享队列；失败不会阻塞之后的配置操作。
  Future<T> _withFile<T>(Future<T> Function(File target) action) async {
    final target = await _resolveFile();
    final key = target.absolute.uri.normalizePath().toFilePath();
    final previous = _pending[key] ?? Future<void>.value();
    final work = previous.then((_) => action(target));
    final finished = work.then<void>((_) {}, onError: (Object _) {});
    _pending[key] = finished;
    unawaited(
      finished.then((_) {
        if (identical(_pending[key], finished)) _pending.remove(key);
      }),
    );
    return work;
  }

  Future<String?> _readBounded(File target) async {
    final RandomAccessFile input;
    try {
      input = await target.open();
    } on PathNotFoundException {
      final parentType = await FileSystemEntity.type(target.parent.path);
      if (parentType == FileSystemEntityType.directory ||
          parentType == FileSystemEntityType.notFound) {
        return null;
      }
      rethrow;
    }
    try {
      if ((await target.stat()).type != FileSystemEntityType.file) {
        throw const FileSystemException('本地设置不可用');
      }
      final bytes = await input.read(_maxBytes + 1);
      if (bytes.length > _maxBytes) {
        throw const FormatException('本地设置不可用');
      }
      return utf8.decode(bytes);
    } finally {
      await input.close();
    }
  }

  /// 先写同目录临时文件，替换成功前不改动已有配置。
  Future<void> _writeAtomic(File target, String content) async {
    final temporary = File('${target.path}.tmp');
    try {
      final bytes = utf8.encode(content);
      if (bytes.length > _maxBytes) {
        throw const FileSystemException('本地设置不可用');
      }
      await target.parent.create(recursive: true);
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(target.path);
    } finally {
      try {
        await temporary.delete();
      } catch (_) {
        // 删除残留失败不覆盖原操作结果，也不公开底层异常。
      }
    }
  }

  @override
  Future<AppSettings> load() async {
    try {
      return await _withFile((target) async {
        final raw = await _readBounded(target);
        return raw == null
            ? const AppSettings()
            : AppSettings.fromJson(jsonDecode(raw));
      });
    } catch (_) {
      // JSON 解析错误的 source 可能包含整个文件，必须重新构造安全错误。
      throw const FormatException('本地设置不可用');
    }
  }

  @override
  Future<void> save(AppSettings settings) async {
    try {
      await _withFile(
        (target) => _writeAtomic(target, jsonEncode(settings.toJson())),
      );
    } catch (_) {
      throw const FileSystemException('本地设置不可用');
    }
  }
}
