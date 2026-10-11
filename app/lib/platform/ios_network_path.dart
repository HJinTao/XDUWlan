import 'dart:async';

import 'package:flutter/services.dart';

import '../core/domain.dart';

/// iOS 原生路径只暴露可用于安全决策的类别和可用性。
class NetworkPathSnapshot {
  const NetworkPathSnapshot({required this.link, required this.available});

  final NetworkLink link;
  final bool available;

  static const unavailable = NetworkPathSnapshot(
    link: NetworkLink.unknown,
    available: false,
  );

  factory NetworkPathSnapshot.fromPayload(Object? payload) {
    if (payload is! Map) return unavailable;
    final linkValue = payload['link'];
    final availableValue = payload['available'];
    if (linkValue is! String || availableValue is! bool) return unavailable;
    final link = _linkFromName(linkValue);
    if (link == null) return unavailable;
    return NetworkPathSnapshot(link: link, available: availableValue);
  }

  Map<String, Object> toPayload() => <String, Object>{
    'link': link.name,
    'available': available,
  };

  @override
  bool operator ==(Object other) =>
      other is NetworkPathSnapshot &&
      other.link == link &&
      other.available == available;

  @override
  int get hashCode => Object.hash(link, available);
}

NetworkLink? _linkFromName(String value) {
  for (final link in NetworkLink.values) {
    if (link.name == value) return link;
  }
  return null;
}

abstract interface class NetworkPathSource {
  Future<NetworkPathSnapshot> current();
  Stream<NetworkPathSnapshot> get pathUpdates;
}

/// 通过固定 MethodChannel 接收 iOS NWPathMonitor 的脱敏事实。
class MethodChannelNetworkPathSource implements NetworkPathSource {
  MethodChannelNetworkPathSource({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName) {
    _channel.setMethodCallHandler(_handleCall);
  }

  static const _channelName = 'cn.xduwlan/iosNetwork';
  final MethodChannel _channel;
  final StreamController<NetworkPathSnapshot> _updates =
      StreamController<NetworkPathSnapshot>.broadcast();
  bool _disposed = false;

  @override
  Stream<NetworkPathSnapshot> get pathUpdates => _updates.stream;

  @override
  Future<NetworkPathSnapshot> current() async {
    if (_disposed) return NetworkPathSnapshot.unavailable;
    try {
      return NetworkPathSnapshot.fromPayload(
        await _channel.invokeMethod<Object?>('currentPath'),
      );
    } on MissingPluginException {
      return NetworkPathSnapshot.unavailable;
    } on PlatformException {
      return NetworkPathSnapshot.unavailable;
    } on StateError {
      return NetworkPathSnapshot.unavailable;
    }
  }

  Future<Object?> _handleCall(MethodCall call) async {
    if (call.method != 'pathUpdates') return null;
    final snapshot = _tryFromPayload(call.arguments);
    if (snapshot != null && !_disposed) _updates.add(snapshot);
    return null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _channel.setMethodCallHandler(null);
    _updates.close();
  }
}

NetworkPathSnapshot? _tryFromPayload(Object? payload) {
  if (payload is! Map) return null;
  final linkValue = payload['link'];
  final availableValue = payload['available'];
  if (linkValue is! String || availableValue is! bool) return null;
  final link = _linkFromName(linkValue);
  if (link == null) return null;
  return NetworkPathSnapshot(link: link, available: availableValue);
}
