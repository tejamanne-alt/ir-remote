// Transport names and reasons the UI shows come from the ARB file.
import 'package:flutter_test/flutter_test.dart';
import 'package:ir_core/ir_core.dart';
import 'package:irremote/l10n/app_localizations_en.dart';
import 'package:irremote/services/send_service.dart';
import 'package:irremote/transports/android_consumer_ir.dart';
import 'package:irremote/ui/labels.dart';

/// English with marked strings, to prove which ARB entry was used.
final class _Marked extends AppLocalizationsEn {
  @override
  String get transportThisPhone => '<this phone>';

  @override
  String get simulatorName => '<simulator>';

  @override
  String get resultBuiltInNoEmitter => '<no emitter>';

  @override
  String get resultBuiltInPermission => '<permission>';
}

void main() {
  final l = _Marked();

  test(
    'the built-in emitter and the simulator are named from the ARB file',
    () {
      expect(
        transportLabel(l, TransportKind.builtIn, 'This phone'),
        '<this phone>',
      );
      expect(
        transportLabel(l, TransportKind.simulated, 'Simulator'),
        '<simulator>',
      );
      expect(transportLabel(l, TransportKind.espBridge, 'Hall'), 'Hall');
      final timeout = outcomeMessage(
        l,
        const SendOutcome(
          TransmitTimeout(Duration(seconds: 5)),
          transportName: 'This phone',
          transportKind: TransportKind.builtIn,
        ),
      )!;
      expect(timeout, contains('<this phone>'));
      expect(timeout, isNot(contains('This phone')));
    },
  );

  test("the built-in emitter's reasons are localized", () {
    String? m(String detail) => outcomeMessage(
      l,
      SendOutcome(
        TransmitTransportUnavailable(detail),
        transportName: 'This phone',
        transportKind: TransportKind.builtIn,
      ),
    );
    expect(m(ConsumerIrDetail.noEmitter), '<no emitter>');
    expect(m(ConsumerIrDetail.permission), '<permission>');
    expect(m(ConsumerIrDetail.channelMissing), isNot(contains('channel')));
  });
}
