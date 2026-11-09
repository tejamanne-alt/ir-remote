// Broadlink hello / discovery over UDP.
//
// Independent Dart implementation; protocol facts taken from the
// MIT-licensed python-broadlink (read, not translated):
// * https://github.com/mjg59/python-broadlink
//   at commit 730853e5faf2cf979596662faf9def2b1f8fee6d
//   - protocol.md "Network discovery": the 48-byte hello packet sent to
//     UDP port 80, broadcast to 255.255.255.255, and its reply (devtype at
//     0x34, MAC at 0x3a).
//   - broadlink/device.py `scan` and `hello`: resending the hello every
//     second until the timeout, unicast hello to one address (works for
//     locked devices), reply name at 0x40 and lock flag at 0x7f,
//     de-duplicating replies by (address, MAC, devtype).
// * https://github.com/DAB-LABS/python-broadlink
//   at commit 6c6567ddeba8905537e0049a1343ebd0e5e165a2
//   - broadlink_async/device.py: the same discovery flow.

/// Finding Broadlink devices: unicast hello to an address the user typed
/// (the primary path) and opt-in broadcast discovery.
///
/// iOS only lets an app broadcast or multicast with Apple's multicast
/// networking entitlement, so the app asks for the hub's IP address and
/// uses [broadlinkHello]. Unicast to a LAN address still needs the local
/// network permission prompt on iOS 14+. Broadcast ([discoverBroadlinkDevices]
/// with `broadcast: true`) is off by default.
library;

import 'dart:async';
import 'dart:io';

import 'broadlink_protocol.dart';

/// A device that answered a hello.
final class BroadlinkDeviceInfo {
  /// Creates a device descriptor.
  BroadlinkDeviceInfo({
    required this.address,
    required this.port,
    required List<int> mac,
    required this.devtype,
    this.name,
    this.isLocked,
  }) : mac = List.unmodifiable(mac) {
    if (mac.length != 6) {
      throw ArgumentError.value(mac.length, 'mac.length', 'must be 6');
    }
  }

  /// Where the device answered from.
  final InternetAddress address;

  /// UDP port (80 on real devices).
  final int port;

  /// MAC in display order.
  final List<int> mac;

  /// Device type; see [broadlinkRmModels].
  final int devtype;

  /// Name set in the Broadlink app, if reported.
  final String? name;

  /// Whether the device is locked against local control, if reported. A
  /// locked device answers hello but refuses auth until it is unlocked in
  /// the Broadlink app.
  final bool? isLocked;

  /// The RM model, or `null` when [devtype] is not a known RM device.
  BroadlinkModel? get model => broadlinkModelFor(devtype);

  /// MAC as lowercase colon-separated hex.
  String get macString => formatBroadlinkMac(mac);

  /// [devtype] as `0x` and four hex digits.
  String get devtypeHex => '0x${devtype.toRadixString(16).padLeft(4, '0')}';

  @override
  String toString() =>
      'BroadlinkDeviceInfo(${name ?? '?'} ${model?.name ?? 'unknown'} '
      '$devtypeHex at ${address.address}:$port, mac $macString'
      '${isLocked == true ? ', locked' : ''})';
}

/// Sends a unicast hello to [address] and returns the device that answers,
/// or `null` when nothing answers within [timeout]. The hello is resent
/// every [resendInterval]. Only replies from [address]:[port] count.
///
/// Throws [BroadlinkNetworkException] when no socket can be opened or the
/// hello cannot be sent.
Future<BroadlinkDeviceInfo?> broadlinkHello(
  InternetAddress address, {
  int port = broadlinkDefaultPort,
  Duration timeout = const Duration(seconds: 3),
  Duration resendInterval = const Duration(seconds: 1),
  InternetAddress? bindAddress,
}) async {
  final found = await _probe(
    targets: [(address: address, port: port)],
    broadcast: false,
    timeout: timeout,
    resendInterval: resendInterval,
    bindAddress: bindAddress,
    firstOnly: true,
  );
  return found.isEmpty ? null : found.first;
}

/// Sends hellos and collects every device that answers within [timeout].
///
/// A unicast hello goes to each of [addresses]. A broadcast hello goes to
/// [broadcastAddress] (255.255.255.255 by default) only when [broadcast] is
/// true; it is off by default because iOS needs a special entitlement for
/// it and many networks drop broadcast between Wi-Fi clients. With no
/// addresses and broadcast off this returns an empty list without touching
/// the network. Replies are de-duplicated by address, MAC and devtype.
///
/// Throws [BroadlinkNetworkException] when no socket can be opened or a
/// hello cannot be sent.
Future<List<BroadlinkDeviceInfo>> discoverBroadlinkDevices({
  Iterable<InternetAddress> addresses = const [],
  bool broadcast = false,
  InternetAddress? broadcastAddress,
  int port = broadlinkDefaultPort,
  Duration timeout = const Duration(seconds: 3),
  Duration resendInterval = const Duration(seconds: 1),
  InternetAddress? bindAddress,
}) {
  final targets = <({InternetAddress address, int port})>[
    for (final a in addresses) (address: a, port: port),
    if (broadcast)
      (
        address: broadcastAddress ?? InternetAddress('255.255.255.255'),
        port: port,
      ),
  ];
  if (targets.isEmpty) return Future.value(const []);
  return _probe(
    targets: targets,
    broadcast: broadcast,
    timeout: timeout,
    resendInterval: resendInterval,
    bindAddress: bindAddress,
    firstOnly: false,
  );
}

Future<List<BroadlinkDeviceInfo>> _probe({
  required List<({InternetAddress address, int port})> targets,
  required bool broadcast,
  required Duration timeout,
  required Duration resendInterval,
  required InternetAddress? bindAddress,
  required bool firstOnly,
}) async {
  final RawDatagramSocket socket;
  try {
    socket = await RawDatagramSocket.bind(
      bindAddress ?? InternetAddress.anyIPv4,
      0,
    );
  } on SocketException catch (e) {
    throw BroadlinkNetworkException('cannot open a UDP socket: ${e.message}');
  }
  final results = <BroadlinkDeviceInfo>[];
  final seen = <String>{};
  final done = Completer<void>();
  BroadlinkNetworkException? sendError;

  void finish() {
    if (!done.isCompleted) done.complete();
  }

  void sendAll() {
    final packet = buildBroadlinkHelloPacket(now: DateTime.now());
    for (final t in targets) {
      try {
        socket.send(packet, t.address, t.port);
      } on SocketException catch (e) {
        sendError = BroadlinkNetworkException(
          'cannot send hello to ${t.address.address}:${t.port}: ${e.message}',
        );
        finish();
        return;
      }
    }
  }

  bool fromTarget(Datagram d) =>
      targets.any((t) => t.address == d.address && t.port == d.port);

  final sub = socket.listen(
    (event) {
      if (event != RawSocketEvent.read) return;
      for (var d = socket.receive(); d != null; d = socket.receive()) {
        if (!broadcast && !fromTarget(d)) continue;
        final BroadlinkHelloReply reply;
        try {
          reply = BroadlinkHelloReply.parse(d.data);
        } on BroadlinkFormatException {
          continue; // Our own hello echoed back, or unrelated traffic.
        }
        final key =
            '${d.address.address}|${formatBroadlinkMac(reply.mac)}|'
            '${reply.devtype}';
        if (!seen.add(key)) continue;
        results.add(
          BroadlinkDeviceInfo(
            address: d.address,
            port: d.port,
            mac: reply.mac,
            devtype: reply.devtype,
            name: reply.name,
            isLocked: reply.isLocked,
          ),
        );
        if (firstOnly) finish();
      }
    },
    onError: (Object e) {
      sendError = BroadlinkNetworkException('UDP socket error: $e');
      finish();
    },
  );

  if (broadcast) socket.broadcastEnabled = true;
  sendAll();
  final resend = Timer.periodic(resendInterval, (_) => sendAll());
  final deadline = Timer(timeout, finish);
  try {
    await done.future;
  } finally {
    resend.cancel();
    deadline.cancel();
    await sub.cancel();
    socket.close();
  }
  final error = sendError;
  if (error != null && results.isEmpty) throw error;
  return results;
}
