import 'dart:convert';
import 'dart:io';

enum ThinkPadLabAction { status, down, up, observe }

enum ThinkPadResultCategory { ready, completed, unavailable, rejected, failed }

enum HostLinkCategory { wired, wireless, unavailable, unknown }

class ThinkPadLabFailure implements Exception {
  const ThinkPadLabFailure([this.message = '实验控制器参数或证据目录不可用']);
  final String message;
  @override
  String toString() => message;
}

class ThinkPadLabOptions {
  const ThinkPadLabOptions({
    required this.action,
    required this.evidenceDirectory,
    this.duration = const Duration(seconds: 60),
    this.batchId,
  });

  final ThinkPadLabAction action;
  final String evidenceDirectory;
  final Duration duration;
  final String? batchId;

  static ThinkPadLabOptions parse(List<String> args) {
    final values = <String, String>{};
    for (final argument in args) {
      final separator = argument.indexOf('=');
      if (separator <= 0) throw const FormatException('实验参数不可用');
      final key = argument.substring(0, separator);
      final value = argument.substring(separator + 1);
      if (!{
            '--action',
            '--evidence-directory',
            '--duration-seconds',
            '--batch-id',
          }.contains(key) ||
          values.containsKey(key) ||
          value.isEmpty) {
        throw const FormatException('实验参数不可用');
      }
      values[key] = value;
    }
    final actionText = values['--action'];
    final action = switch (actionText) {
      'status' => ThinkPadLabAction.status,
      'down' => ThinkPadLabAction.down,
      'up' => ThinkPadLabAction.up,
      'observe' => ThinkPadLabAction.observe,
      _ => null,
    };
    final durationText = values['--duration-seconds'] ?? '60';
    final seconds = int.tryParse(durationText);
    final directory = values['--evidence-directory'];
    final batch = values['--batch-id'];
    if (action == null ||
        directory == null ||
        action != ThinkPadLabAction.observe &&
            values.containsKey('--duration-seconds') ||
        !RegExp(r'^[0-9]{1,5}$').hasMatch(durationText) ||
        seconds == null ||
        seconds < 1 ||
        seconds > 10800 ||
        !directory.startsWith('/') ||
        directory.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        batch != null && !RegExp(r'^[A-Za-z0-9._-]{1,80}$').hasMatch(batch)) {
      throw const FormatException('实验参数不可用');
    }
    return ThinkPadLabOptions(
      action: action,
      evidenceDirectory: directory,
      duration: Duration(seconds: seconds),
      batchId: batch,
    );
  }
}

class ProcessResultData {
  const ProcessResultData({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });
  final int exitCode;
  final String stdout;
  final String stderr;
}

abstract interface class ThinkPadProcessRunner {
  Future<ProcessResultData> run(String executable, List<String> arguments);
}

class IoThinkPadProcessRunner implements ThinkPadProcessRunner {
  @override
  Future<ProcessResultData> run(
    String executable,
    List<String> arguments,
  ) async {
    final result = await Process.run(executable, arguments);
    return ProcessResultData(
      exitCode: result.exitCode,
      stdout: result.stdout is String ? result.stdout as String : '',
      stderr: result.stderr is String ? result.stderr as String : '',
    );
  }
}

typedef HostLinkReader = Future<HostLinkCategory> Function();
typedef Clock = DateTime Function();

class ThinkPadObservation {
  const ThinkPadObservation({
    required this.resultCategory,
    this.requests = 0,
    this.submissions = 0,
  });
  final ThinkPadResultCategory resultCategory;
  final int requests;
  final int submissions;
}

typedef ObservationReader = Future<ThinkPadObservation> Function(
  Duration duration,
);

class ThinkPadLabEvent {
  const ThinkPadLabEvent({
    required this.time,
    required this.action,
    required this.resultCategory,
    required this.hostLink,
    required this.protocolRequests,
    required this.protocolSubmissions,
    this.batchId,
  });

  final DateTime time;
  final ThinkPadLabAction action;
  final ThinkPadResultCategory resultCategory;
  final HostLinkCategory hostLink;
  final int protocolRequests;
  final int protocolSubmissions;
  final String? batchId;

  String toJson() => jsonEncode({
    'time': time.toUtc().toIso8601String(),
    'action': action.name,
    'result': resultCategory.name,
    'hostLink': hostLink.name,
    'protocol': {
      'requests': protocolRequests,
      'submissions': protocolSubmissions,
    },
    if (batchId != null) 'batchId': batchId,
  });
}

class ThinkPadLab {
  ThinkPadLab({
    ThinkPadProcessRunner? runner,
    bool? platformIsLinux,
    HostLinkReader? hostLink,
    Clock? clock,
    this.observe,
  }) : runner = runner ?? IoThinkPadProcessRunner(),
       platformIsLinux = platformIsLinux ?? Platform.isLinux,
       hostLink = hostLink ?? (() async => HostLinkCategory.unknown),
       clock = clock ?? DateTime.now;

  static const fixedConnection = 'xduwlan-lab-b';
  final ThinkPadProcessRunner runner;
  final bool platformIsLinux;
  final HostLinkReader hostLink;
  final Clock clock;
  final ObservationReader? observe;

  Future<ThinkPadLabEvent> run(ThinkPadLabOptions options) async {
    if (!platformIsLinux) throw const ThinkPadLabFailure();
    final evidence = await _Evidence.open(options.evidenceDirectory);
    final link = await hostLink();
    if (link != HostLinkCategory.wired) throw const ThinkPadLabFailure();
    var result = ThinkPadResultCategory.failed;
    var requests = 0;
    var submissions = 0;
    switch (options.action) {
      case ThinkPadLabAction.status:
        final process = await runner.run('nmcli', const [
          '-t',
          '-f',
          'NAME',
          'connection',
          'show',
        ]);
        final names = const LineSplitter().convert(process.stdout);
        result = process.exitCode == 0 && names.contains(fixedConnection)
            ? ThinkPadResultCategory.ready
            : ThinkPadResultCategory.unavailable;
      case ThinkPadLabAction.down:
      case ThinkPadLabAction.up:
        final verb = options.action == ThinkPadLabAction.down ? 'down' : 'up';
        final process = await runner.run('nmcli', [
          'connection',
          verb,
          'id',
          fixedConnection,
        ]);
        result = process.exitCode == 0
            ? ThinkPadResultCategory.completed
            : ThinkPadResultCategory.unavailable;
        if (await hostLink() != HostLinkCategory.wired) {
          result = ThinkPadResultCategory.unavailable;
        }
      case ThinkPadLabAction.observe:
        final reader = observe;
        if (reader == null) throw const ThinkPadLabFailure();
        final observation = await reader(options.duration);
        result = observation.resultCategory;
        requests = observation.requests;
        submissions = observation.submissions;
    }
    final finalLink = await hostLink();
    final event = ThinkPadLabEvent(
      time: clock(),
      action: options.action,
      resultCategory: result,
      hostLink: finalLink,
      protocolRequests: requests,
      protocolSubmissions: submissions,
      batchId: options.batchId,
    );
    await evidence.append(event.toJson());
    return event;
  }
}

class _Evidence {
  _Evidence(this.directory);
  final Directory directory;
  File get file => File('${directory.path}/thinkpad-lab.jsonl');

  static Future<_Evidence> open(String path) async {
    final directory = Directory(path);
    await _rejectSymlinkComponents(directory);
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type != FileSystemEntityType.notFound) {
      if (type != FileSystemEntityType.directory ||
          await directory.list(followLinks: false).isEmpty == false) {
        throw const ThinkPadLabFailure();
      }
    }
    await directory.create(recursive: true);
    if (!Platform.isWindows) {
      final result = await Process.run('chmod', ['0700', directory.path]);
      if (result.exitCode != 0) throw const ThinkPadLabFailure();
    }
    return _Evidence(directory);
  }

  static Future<void> _rejectSymlinkComponents(Directory directory) async {
    final absolute = directory.absolute.path;
    var current = Directory(Platform.pathSeparator);
    for (final component
        in absolute
            .split(Platform.pathSeparator)
            .where((part) => part.isNotEmpty)) {
      current = Directory(
        current.path == Platform.pathSeparator
            ? '${Platform.pathSeparator}$component'
            : '${current.path}${Platform.pathSeparator}$component',
      );
      final trustedSystemAlias =
          (Platform.isMacOS &&
          (current.path == '/var' || current.path == '/tmp'));
      if (!trustedSystemAlias &&
          await FileSystemEntity.type(current.path, followLinks: false) ==
              FileSystemEntityType.link) {
        throw const ThinkPadLabFailure();
      }
    }
  }

  Future<void> append(String line) async {
    await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
    if (!Platform.isWindows) {
      final result = await Process.run('chmod', ['0600', file.path]);
      if (result.exitCode != 0) throw const ThinkPadLabFailure();
    }
  }
}

Future<void> main(List<String> args) async {
  try {
    final options = ThinkPadLabOptions.parse(args);
    final event = await ThinkPadLab(platformIsLinux: Platform.isLinux)
        .run(options);
    stdout.writeln(event.toJson());
  } on FormatException {
    stderr.writeln('{"result":"rejected"}');
    exitCode = 64;
  } on ThinkPadLabFailure {
    stderr.writeln('{"result":"failed"}');
    exitCode = 65;
  } catch (_) {
    stderr.writeln('{"result":"failed"}');
    exitCode = 70;
  }
}
