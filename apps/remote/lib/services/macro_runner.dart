/// Runs macros step by step with visible progress and cancellation.
library;

import 'dart:async';

import '../data/macros.dart';
import '../data/repositories.dart';
import 'send_service.dart';

/// Progress of a running macro.
sealed class MacroProgress {
  const MacroProgress();
}

/// About to run step [index] (0-based) of [total].
final class MacroStepStarted extends MacroProgress {
  /// Creates the event.
  const MacroStepStarted(this.index, this.total);

  /// Step index.
  final int index;

  /// Step count.
  final int total;
}

/// Step [index] failed; the macro stops.
final class MacroStepFailed extends MacroProgress {
  /// Creates the event.
  const MacroStepFailed(this.index, this.outcome, {this.missingDevice = false});

  /// Step index.
  final int index;

  /// What happened, or `null` when the remote no longer exists.
  final SendOutcome? outcome;

  /// The step's remote was deleted.
  final bool missingDevice;
}

/// Every step ran.
final class MacroCompleted extends MacroProgress {
  /// Creates the event.
  const MacroCompleted();
}

/// The user cancelled.
final class MacroCancelled extends MacroProgress {
  /// Creates the event.
  const MacroCancelled(this.afterSteps);

  /// Steps completed before cancelling.
  final int afterSteps;
}

/// A running macro.
final class MacroRun {
  MacroRun._();

  // Closed by the runner after the terminal event.
  // ignore: close_sinks
  final StreamController<MacroProgress> _events = StreamController.broadcast();
  final Completer<void> _cancel = Completer<void>();

  /// Progress events; the stream closes after a terminal event.
  Stream<MacroProgress> get events => _events.stream;

  /// Whether [cancel] was called.
  bool get isCancelled => _cancel.isCompleted;

  /// Stops after the current step; pending delays end at once.
  void cancel() {
    if (!_cancel.isCompleted) _cancel.complete();
  }
}

/// Runs macros through the send pipeline.
final class MacroRunner {
  /// Creates the runner.
  MacroRunner({required this.send, required this.devices});

  /// Send pipeline.
  final SendService send;

  /// For loading each step's remote.
  final DeviceRepository devices;

  /// Starts [macro]. Listen to [MacroRun.events] for progress.
  MacroRun run(Macro macro) {
    final r = MacroRun._();
    scheduleMicrotask(() => _execute(macro, r));
    return r;
  }

  Future<void> _execute(Macro m, MacroRun r) async {
    final total = m.steps.length;
    try {
      for (var i = 0; i < total; i++) {
        if (r.isCancelled) {
          r._events.add(MacroCancelled(i));
          return;
        }
        r._events.add(MacroStepStarted(i, total));
        final step = m.steps[i];
        final device = await devices.load(step.deviceId);
        if (device == null) {
          r._events.add(MacroStepFailed(i, null, missingDevice: true));
          return;
        }
        final o = await send.sendKey(device, step.key);
        if (!o.ok) {
          r._events.add(MacroStepFailed(i, o));
          return;
        }
        if (step.delay > Duration.zero) {
          // A cancellable wait: the timer is stopped on cancel, not left
          // running for up to a minute.
          final waited = Completer<void>();
          final timer = Timer(step.delay, waited.complete);
          await Future.any([waited.future, r._cancel.future]);
          timer.cancel();
        }
      }
      r._events.add(
        r.isCancelled ? MacroCancelled(total) : const MacroCompleted(),
      );
    } finally {
      await r._events.close();
    }
  }
}
