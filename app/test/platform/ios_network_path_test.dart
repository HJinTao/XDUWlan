import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xduwlan_app/core/domain.dart';
import 'package:xduwlan_app/platform/ios_network_path.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('maps every native link value without retaining raw path data', () {
    for (final link in NetworkLink.values) {
      final snapshot = NetworkPathSnapshot.fromPayload(<String, Object?>{
        'link': link.name,
        'available': true,
      });
      expect(snapshot.link, link);
      expect(snapshot.available, isTrue);
    }
  });

  test('malformed native payload becomes unavailable unknown path', () {
    expect(
      NetworkPathSnapshot.fromPayload(const <String, Object?>{}),
      const NetworkPathSnapshot(link: NetworkLink.unknown, available: false),
    );
    expect(
      NetworkPathSnapshot.fromPayload(<String, Object?>{
        'link': 'wifi',
        'available': 'yes',
      }),
      const NetworkPathSnapshot(link: NetworkLink.unknown, available: false),
    );
    expect(
      NetworkPathSnapshot.fromPayload('raw path'),
      const NetworkPathSnapshot(link: NetworkLink.unknown, available: false),
    );
  });

  test('missing native channel is safe and unavailable', () async {
    const channel = MethodChannel('cn.xduwlan.test.missingNetwork');
    final source = MethodChannelNetworkPathSource(channel: channel);
    addTearDown(source.dispose);

    final snapshot = await source.current();

    expect(
      snapshot,
      const NetworkPathSnapshot(link: NetworkLink.unknown, available: false),
    );
  });

  test('native currentPath payload is mapped through the source', () async {
    const channel = MethodChannel('cn.xduwlan.test.network');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'currentPath');
          return <String, Object?>{'link': 'wifi', 'available': true};
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final source = MethodChannelNetworkPathSource(channel: channel);
    addTearDown(source.dispose);

    expect(
      await source.current(),
      const NetworkPathSnapshot(link: NetworkLink.wifi, available: true),
    );
  });
}
