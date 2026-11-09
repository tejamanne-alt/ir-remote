/// Pure Dart IR knowledge for the IR remote app.
///
/// Signal model and validation, protocol codecs, Pronto and raw formats,
/// code-set model, key vocabulary and the AC state engine. No Flutter and no
/// dart:io.
library;

export 'src/ac/ac_state.dart';
export 'src/codecs/jvc.dart';
export 'src/codecs/lg.dart';
export 'src/codecs/nec.dart';
export 'src/codecs/panasonic.dart';
export 'src/codecs/protocol.dart';
export 'src/codecs/rc5.dart';
export 'src/codecs/rc6.dart';
export 'src/codecs/registry.dart';
export 'src/codecs/sharp.dart';
export 'src/codecs/sony.dart';
export 'src/codecs/timing.dart' show TimingTolerance;
export 'src/codecs/toggle.dart';
export 'src/codeset/code_set.dart';
export 'src/command/keys.dart';
export 'src/formats/pronto.dart';
export 'src/formats/raw.dart';
export 'src/signal/ir_signal.dart';
export 'src/signal/validation.dart';
export 'src/transport/transport.dart';
