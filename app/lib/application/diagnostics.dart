import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/domain.dart';
import '../platform/application_support.dart';

class DiagnosticRecord {
  const DiagnosticRecord({
    required this.time,
    required this.source,
    required this.action,
    required this.network,
    required this.outcome,
    required this.failure,
    required this.elapsedMilliseconds,
  });

  final DateTime time;
  final OperationSource source;
  final OperationKind action;
  final NetworkState network;
  final RecoveryOutcome? outcome;
  final FailureCode? failure;
  final int elapsedMilliseconds;

  factory DiagnosticRecord.fromReport(OperationReport report) {
    if (report.elapsed.isNegative) {
      throw const FormatException('本地诊断记录不可用');
    }
    return DiagnosticRecord(
      time: report.completedAt,
      source: report.source,
      action: report.kind,
      network: report.network,
      outcome: report.outcome,
      failure: report.failure,
      elapsedMilliseconds: report.elapsed.inMilliseconds,
    );
  }

  Map<String, dynamic> toJson() {
    if (elapsedMilliseconds < 0) {
      throw const FormatException('本地诊断记录不可用');
    }
    return {
      'time': time.toIso8601String(),
      'source': source.name,
      'action': action.name,
      'network': network.name,
      if (outcome != null) 'outcome': outcome!.name,
      if (failure != null) 'failure': failure!.name,
      'elapsedMilliseconds': elapsedMilliseconds,
    };
  }

  static const _fields = {
    'time',
    'source',
    'action',
    'network',
    'outcome',
    'failure',
    'elapsedMilliseconds',
  };

  factory DiagnosticRecord.fromJson(Map<String, dynamic> raw) {
    try {
      if (raw.keys.any((key) => !_fields.contains(key))) {
        throw const FormatException();
      }
      final timeText = raw['time'];
      final elapsed = raw['elapsedMilliseconds'];
      if (timeText is! String || elapsed is! int || elapsed < 0) {
        throw const FormatException();
      }
      final time = DateTime.parse(timeText);
      // DateTime.parse 会将溢出的日期自动进位；只接受本程序保存的标准格式。
      if (time.toIso8601String() != timeText) throw const FormatException();
      return DiagnosticRecord(
        time: time,
        source: OperationSource.values.byName(raw['source'] as String),
        action: OperationKind.values.byName(raw['action'] as String),
        network: NetworkState.values.byName(raw['network'] as String),
        outcome: raw['outcome'] == null
            ? null
            : RecoveryOutcome.values.byName(raw['outcome'] as String),
        failure: raw['failure'] == null
            ? null
            : FailureCode.values.byName(raw['failure'] as String),
        elapsedMilliseconds: elapsed,
      );
    } catch (_) {
      throw const FormatException('本地诊断记录不可用');
    }
  }
}

abstract interface class DiagnosticStore {
  Future<List<DiagnosticRecord>> load();
  Future<void> append(DiagnosticRecord record);
  Future<void> clear();
}

class LocalDiagnosticStore implements DiagnosticStore {
  LocalDiagnosticStore({this.directory, this.file});
  final Directory? directory;
  final File? file;
  static const fileName = 'diagnostics.json';
  static const maxRecords = 50;
  static const _maxBytes = 64 * 1024;
  static final Map<String, Future<void>> _pending = {};

  Future<File> _resolveFile() async {
    if (file case final configured?) return configured;
    final root = directory ?? await resolveApplicationSupportDirectory();
    return File('${root.path}/$fileName');
  }

  /// 同一路径的实例共享队列，追加、清空和读取按调用顺序执行。
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
        throw const FileSystemException('本地诊断记录不可用');
      }
      // 在解码前限制读取量，避免损坏或被替换的大文件占用无界内存。
      final bytes = await input.read(_maxBytes + 1);
      if (bytes.length > _maxBytes) throw const FormatException();
      return utf8.decode(bytes);
    } finally {
      await input.close();
    }
  }

  Future<void> _deleteIfPresent(File target) async {
    try {
      await target.delete();
    } on PathNotFoundException {
      // 缺失文件已经满足删除目标。
    }
  }

  Future<void> _quarantine(File target) async {
    final quarantine = File('${target.path}.corrupt');
    await _deleteIfPresent(quarantine);
    await target.rename(quarantine.path);
  }

  Future<List<DiagnosticRecord>> _load(File target) async {
    try {
      final content = await _readBounded(target);
      if (content == null) return [];
      final raw = jsonDecode(content);
      if (raw is! List || raw.length > maxRecords) {
        throw const FormatException();
      }
      final records = <DiagnosticRecord>[];
      for (final item in raw) {
        if (item is! Map<String, dynamic>) throw const FormatException();
        records.add(DiagnosticRecord.fromJson(item));
      }
      records.sort((a, b) => b.time.compareTo(a.time));
      return records;
    } on FormatException {
      // 损坏文件整体隔离，不能悄悄忽略其中未知或不安全的字段。
      await _quarantine(target);
      return [];
    }
  }

  /// 临时文件与目标处于同一目录，替换前保留已有完整记录。
  Future<void> _writeAtomic(File target, List<DiagnosticRecord> records) async {
    final temporary = File('${target.path}.tmp');
    try {
      final bytes = utf8.encode(
        jsonEncode(records.map((item) => item.toJson()).toList()),
      );
      if (records.length > maxRecords || bytes.length > _maxBytes) {
        throw const FileSystemException('本地诊断记录不可用');
      }
      await target.parent.create(recursive: true);
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(target.path);
    } finally {
      try {
        await temporary.delete();
      } catch (_) {
        // 清理失败不覆盖原操作结果，也不公开底层异常。
      }
    }
  }

  @override
  Future<List<DiagnosticRecord>> load() async {
    try {
      return await _withFile(_load);
    } catch (_) {
      throw const FileSystemException('本地诊断记录不可用');
    }
  }

  @override
  Future<void> append(DiagnosticRecord record) async {
    try {
      record.toJson();
      await _withFile((target) async {
        final records = [record, ...await _load(target)]
          ..sort((a, b) => b.time.compareTo(a.time));
        await _writeAtomic(target, records.take(maxRecords).toList());
      });
    } catch (_) {
      throw const FileSystemException('本地诊断记录不可用');
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _withFile((target) async {
        await _deleteIfPresent(target);
        await _deleteIfPresent(File('${target.path}.corrupt'));
        await _deleteIfPresent(File('${target.path}.tmp'));
      });
    } catch (_) {
      throw const FileSystemException('本地诊断记录不可用');
    }
  }
}
