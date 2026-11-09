// Hello and discovery against FakeBroadlinkDevice on 127.0.0.1.
//
// Protocol per the MIT-licensed python-broadlink: mjg59/python-broadlink at
// 730853e5faf2cf979596662faf9def2b1f8fee6d and the DAB-LABS fork at
// 6c6567ddeba8905537e0049a1343ebd0e5e165a2; see the header of
// lib/src/broadlink/broadlink_protocol.dart for what each specifies.

import 'package:ir_transports/src/broadlink/broadlink_discovery.dart';
import 'package:ir_transports/src/broadlink/broadlink_protocol.dart';
import 'package:test/test.dart';

import 'fake_broadlink_device.dart';

const timeout = Duration(milliseconds: 250);
const resend = Duration(milliseconds: 60);

void main() {
  late FakeBroadlinkDevice fake;

  setUp(() async {
    fake = await FakeBroadlinkDevice.start(name: 'Living room');
    addTearDown(fake.close);
  });

  test('unicast hello returns the device descriptor', () async {
    final info = await broadlinkHello(
      fake.address,
      port: fake.port,
      timeout: timeout,
      resendInterval: resend,
    );
    expect(info, isNotNull);
    expect(info!.address, fake.address);
    expect(info.port, fake.port);
    expect(info.macString, 'aa:bb:cc:dd:ee:ff');
    expect(info.devtype, 0x520c);
    expect(info.devtypeHex, '0x520c');
    expect(info.name, 'Living room');
    expect(info.isLocked, isFalse);
    expect(info.model?.name, 'RM4 mini');
    expect(info.model?.family, BroadlinkFamily.rm4);
  });

  test('unicast hello returns null when nothing answers', () async {
    fake.silent = true;
    final info = await broadlinkHello(
      fake.address,
      port: fake.port,
      timeout: timeout,
      resendInterval: resend,
    );
    expect(info, isNull);
    expect(fake.hellos, greaterThan(1), reason: 'hello is resent');
  });

  test('broadcast is off by default and nothing is sent', () async {
    final found = await discoverBroadlinkDevices(port: fake.port);
    expect(found, isEmpty);
    expect(fake.requests, isEmpty);
  });

  test('broadcast discovery when enabled, de-duplicated', () async {
    // The test cannot rely on a LAN broadcast; point the "broadcast" at
    // loopback, which exercises the same code path with SO_BROADCAST set.
    final found = await discoverBroadlinkDevices(
      broadcast: true,
      broadcastAddress: fake.address,
      port: fake.port,
      timeout: timeout,
      resendInterval: resend,
    );
    expect(fake.hellos, greaterThan(1));
    expect(found, hasLength(1));
    expect(found.single.macString, 'aa:bb:cc:dd:ee:ff');
  });

  test('unicast discovery of several addresses', () async {
    final other = await FakeBroadlinkDevice.start(
      devtype: 0x2737,
      mac: const [1, 2, 3, 4, 5, 6],
      name: 'Bedroom',
    );
    addTearDown(other.close);
    // Both fakes listen on loopback; give each its own port by probing
    // them one by one through the list API.
    final a = await discoverBroadlinkDevices(
      addresses: [fake.address],
      port: fake.port,
      timeout: timeout,
      resendInterval: resend,
    );
    final b = await discoverBroadlinkDevices(
      addresses: [other.address],
      port: other.port,
      timeout: timeout,
      resendInterval: resend,
    );
    expect(a.single.name, 'Living room');
    expect(b.single.name, 'Bedroom');
    expect(b.single.model?.family, BroadlinkFamily.rm2);
  });
}
