// A fake Broadlink RM hub for end-to-end tests: UDP on 127.0.0.1 with an
// ephemeral port, speaking enough of the protocol (hello, auth, send data,
// enter learning, check data, cancel learning) to exercise
// BroadlinkTransport. Device-side framing is written here from the
// protocol description (python-broadlink protocol.md, MIT; see the header
// of lib/src/broadlink/broadlink_protocol.dart) rather than reusing the
// client's RM framing helpers.

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ir_transports/src/broadlink/broadlink_discovery.dart';
import 'package:ir_transports/src/broadlink/broadlink_protocol.dart';

/// What the fake does with a command encrypted under a key it no longer
/// uses.
enum StaleKeyReply {
  /// Reply with error -7 (control key expired).
  errorCode,

  /// Reply "success" with a payload encrypted under the new key, which the
  /// client cannot decrypt.
  encryptedWithNewKey,
}

/// One datagram the fake received.
final class FakeRequest {
  FakeRequest(this.at, this.packetType, this.command);

  /// When it arrived.
  final DateTime at;

  /// Packet type (0x06 for hello).
  final int packetType;

  /// RM command code for packet type 0x6a, else null.
  final int? command;
}

/// The fake hub.
final class FakeBroadlinkDevice {
  FakeBroadlinkDevice._(
    this._socket,
    this._random, {
    required this.devtype,
    required this.mac,
    required this.name,
    required this.locked,
  }) {
    _key = _randomKey();
    _id = _random.nextInt(1 << 30) + 1;
    _sub = _socket.listen(_onEvent);
  }

  /// Starts a fake on 127.0.0.1 with an ephemeral port.
  static Future<FakeBroadlinkDevice> start({
    int devtype = 0x520c, // RM4 mini
    List<int> mac = const [0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff],
    String name = 'Fake RM4',
    bool locked = false,
    int seed = 1,
  }) async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    return FakeBroadlinkDevice._(
      socket,
      Random(seed),
      devtype: devtype,
      mac: mac,
      name: name,
      locked: locked,
    );
  }

  final RawDatagramSocket _socket;
  late final StreamSubscription<RawSocketEvent> _sub;
  final Random _random;

  /// Device type reported in hello replies.
  final int devtype;

  /// MAC in display order.
  final List<int> mac;

  /// Name reported in hello replies.
  final String name;

  /// Lock flag reported in hello replies.
  final bool locked;

  late Uint8List _key;
  late int _id;
  bool _everAuthed = false;

  // Behaviour switches.

  /// Drop every datagram.
  bool silent = false;

  /// Answer hello and auth, drop commands.
  bool silentToCommands = false;

  /// How to answer a command encrypted under a stale key.
  StaleKeyReply staleKeyReply = StaleKeyReply.errorCode;

  /// Answer every command with -7, even after a fresh auth.
  bool alwaysExpired = false;

  /// Error code for send-data, or null for success.
  int? sendDataError;

  /// Ack send-data with error 0 but a payload the client cannot decrypt
  /// (the hub has transmitted; only the reply is garbled).
  bool garbleSendDataReply = false;

  /// The capture check-data returns while learning, after
  /// [pollsBeforeCapture] polls.
  Uint8List? capture;

  /// Polls answered "nothing yet" before [capture] is returned.
  int pollsBeforeCapture = 1;

  // Observations.

  /// Every datagram received, in order (including dropped ones).
  final List<FakeRequest> requests = [];

  /// IR payloads received via send-data, without padding.
  final List<Uint8List> sentIr = [];

  /// Number of auth requests answered.
  int auths = 0;

  /// Commands rejected because they used a stale key.
  int staleRejections = 0;

  /// Whether the fake is in learning mode.
  bool learning = false;

  int _pollsSinceArm = 0;

  /// The fake's address.
  InternetAddress get address => InternetAddress.loopbackIPv4;

  /// The fake's UDP port.
  int get port => _socket.port;

  /// Descriptor as hello would return it.
  BroadlinkDeviceInfo get info => BroadlinkDeviceInfo(
    address: address,
    port: port,
    mac: mac,
    devtype: devtype,
    name: name,
    isLocked: locked,
  );

  /// Requests of [command] received so far.
  int countCommand(int command) =>
      requests.where((r) => r.command == command).length;

  /// Hello packets received so far.
  int get hellos =>
      requests.where((r) => r.packetType == BroadlinkPacketType.hello).length;

  /// Changes the session key and id, as if the device had rebooted or
  /// another client had re-paired it.
  void rotateKey() {
    _key = _randomKey();
    _id = _random.nextInt(1 << 30) + 1;
  }

  /// Stops the fake.
  Future<void> close() async {
    await _sub.cancel();
    _socket.close();
  }

  Uint8List _randomKey() =>
      Uint8List.fromList(List.generate(16, (_) => _random.nextInt(256)));

  bool get _rm4 => broadlinkModelFor(devtype)?.family != BroadlinkFamily.rm2;

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    for (var d = _socket.receive(); d != null; d = _socket.receive()) {
      _onDatagram(d);
    }
  }

  void _onDatagram(Datagram d) {
    final data = d.data;
    if (data.length == 0x30 && data[0x26] == BroadlinkPacketType.hello) {
      requests.add(
        FakeRequest(DateTime.now(), BroadlinkPacketType.hello, null),
      );
      if (!silent) _reply(d, _helloReply());
      return;
    }
    final BroadlinkFrame frame;
    try {
      frame = BroadlinkFrame.parse(data);
    } on BroadlinkFormatException {
      requests.add(FakeRequest(DateTime.now(), -1, null));
      return;
    }
    switch (frame.packetType) {
      case BroadlinkPacketType.auth:
        requests.add(FakeRequest(DateTime.now(), frame.packetType, null));
        if (silent) return;
        _onAuth(d, frame);
      case BroadlinkPacketType.command:
        _onCommand(d, frame);
      default:
        requests.add(FakeRequest(DateTime.now(), frame.packetType, null));
    }
  }

  Uint8List _helloReply() {
    final r = Uint8List(0x80);
    r[0x26] = 0x07;
    r[0x34] = devtype & 0xff;
    r[0x35] = devtype >> 8;
    for (var i = 0; i < 6; i++) {
      r[0x3a + i] = mac[5 - i];
    }
    final n = name.codeUnits;
    r.setRange(0x40, 0x40 + n.length, n);
    r[0x7f] = locked ? 1 : 0;
    final sum = broadlinkChecksum(r);
    r[0x20] = sum & 0xff;
    r[0x21] = sum >> 8;
    return r;
  }

  void _onAuth(Datagram d, BroadlinkFrame frame) {
    final initial = BroadlinkCipher.initial();
    final plain = initial.decrypt(frame.encryptedPayload);
    if (plain.length != 0x50 || plain[0x04] != 0x31) return;
    if (_everAuthed) {
      // A new auth hands out a fresh key, like a device that rotates.
      rotateKey();
    }
    _everAuthed = true;
    auths++;
    final reply = Uint8List(0x14);
    reply[0] = _id & 0xff;
    reply[1] = (_id >> 8) & 0xff;
    reply[2] = (_id >> 16) & 0xff;
    reply[3] = (_id >> 24) & 0xff;
    reply.setRange(4, 20, _key);
    _reply(
      d,
      buildBroadlinkFrame(
        packetType: 0x03e9,
        devtype: devtype,
        count: frame.count,
        mac: mac,
        sessionId: 0,
        payload: reply,
        cipher: initial,
      ),
    );
  }

  void _onCommand(Datagram d, BroadlinkFrame frame) {
    final cipher = BroadlinkCipher(_key);
    final plain = cipher.decrypt(frame.encryptedPayload);
    final fresh =
        frame.sessionId == _id &&
        broadlinkChecksum(plain) == frame.payloadChecksum;
    int? command;
    var data = Uint8List(0);
    if (fresh) {
      if (_rm4) {
        final len = plain[0] | (plain[1] << 8);
        command = plain[2] | (plain[3] << 8);
        data = Uint8List.sublistView(plain, 6, len + 2);
      } else {
        command = plain[0] | (plain[1] << 8);
        data = Uint8List.sublistView(plain, 4);
      }
    }
    requests.add(FakeRequest(DateTime.now(), frame.packetType, command));
    if (silent || silentToCommands) return;
    if (!fresh || alwaysExpired) {
      staleRejections++;
      if (staleKeyReply == StaleKeyReply.encryptedWithNewKey &&
          !alwaysExpired) {
        _replyCommand(d, frame, 0, 0, Uint8List(0));
      } else {
        _replyCommand(d, frame, BroadlinkErrorCode.keyExpired, 0, Uint8List(0));
      }
      return;
    }
    switch (command) {
      case BroadlinkRmCommand.sendData:
        final irLen = data[2] | (data[3] << 8);
        sentIr.add(Uint8List.fromList(data.sublist(0, 4 + irLen)));
        learning = false; // Any send ends a learning session.
        _replyCommand(
          d,
          frame,
          sendDataError ?? 0,
          command!,
          Uint8List(0),
          garble: garbleSendDataReply,
        );
      case BroadlinkRmCommand.enterLearning:
        learning = true;
        _pollsSinceArm = 0;
        _replyCommand(d, frame, 0, command!, Uint8List(0));
      case BroadlinkRmCommand.checkData:
        final c = capture;
        if (learning && c != null && ++_pollsSinceArm > pollsBeforeCapture) {
          learning = false;
          _replyCommand(d, frame, 0, command!, c);
        } else {
          final nothing = _rm4
              ? BroadlinkErrorCode.storageFull
              : BroadlinkErrorCode.readError;
          _replyCommand(d, frame, nothing, command!, Uint8List(0));
        }
      case BroadlinkRmCommand.cancelLearning:
        learning = false;
        _replyCommand(d, frame, 0, command!, Uint8List(0));
      default:
        _replyCommand(
          d,
          frame,
          BroadlinkErrorCode.notSupported,
          command ?? 0,
          Uint8List(0),
        );
    }
  }

  void _replyCommand(
    Datagram d,
    BroadlinkFrame request,
    int errorCode,
    int command,
    Uint8List data, {
    bool garble = false,
  }) {
    final Uint8List plain;
    if (_rm4) {
      plain = Uint8List(6 + data.length);
      plain[0] = (data.length + 4) & 0xff;
      plain[1] = (data.length + 4) >> 8;
      plain[2] = command;
      plain.setRange(6, plain.length, data);
    } else {
      plain = Uint8List(4 + data.length);
      plain[0] = command;
      plain.setRange(4, plain.length, data);
    }
    _reply(
      d,
      buildBroadlinkFrame(
        packetType: 0x03ee,
        devtype: devtype,
        count: request.count,
        mac: mac,
        sessionId: _id,
        payload: plain,
        cipher: garble
            ? BroadlinkCipher(Uint8List.fromList(List.filled(16, 0x5a)))
            : BroadlinkCipher(_key),
        errorCode: errorCode,
      ),
    );
  }

  void _reply(Datagram to, Uint8List bytes) {
    _socket.send(bytes, to.address, to.port);
  }
}

/// Polls [condition] every few milliseconds until it holds or [timeout]
/// passes; returns whether it held.
Future<bool> eventually(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final clock = Stopwatch()..start();
  while (clock.elapsed < timeout) {
    if (condition()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  return condition();
}
