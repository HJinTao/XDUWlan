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

  test(
    'pathUpdates emits valid snapshots and ignores malformed payloads',
    () async {
      const channel = MethodChannel('cn.xduwlan.test.networkUpdates');
      final source = MethodChannelNetworkPathSource(channel: channel);
      addTearDown(source.dispose);
      final events = <NetworkPathSnapshot>[];
      final subscription = source.pathUpdates.listen(events.add);
      addTearDown(subscription.cancel);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Future<void> emit(Object? arguments) async {
        await messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('pathUpdates', arguments),
          ),
          (_) {},
        );
      }

      await emit(<String, Object?>{'link': 'wifi', 'available': true});
      await emit(<String, Object?>{'link': 'wifi', 'available': 'yes'});
      await Future<void>.delayed(Duration.zero);

      expect(events, [
        const NetworkPathSnapshot(link: NetworkLink.wifi, available: true),
      ]);
    },
  );

  test('disposed source ignores late updates and closes its stream', () async {
    const channel = MethodChannel('cn.xduwlan.test.networkDispose');
    final source = MethodChannelNetworkPathSource(channel: channel);
    var events = 0;
    var done = false;
    source.pathUpdates.listen((_) => events++, onDone: () => done = true);
    source.dispose();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('pathUpdates', <String, Object?>{
              'link': 'wifi',
              'available': true,
            }),
          ),
          (_) {},
        );
    await Future<void>.delayed(Duration.zero);

    expect(events, 0);
    expect(done, isTrue);
    expect(
      await source.current(),
      const NetworkPathSnapshot(link: NetworkLink.unknown, available: false),
    );
  });
}
