/// The remote-control button: 48 dp minimum target, haptic tap, visual
/// pulse, hold-to-repeat, and a failure message naming the cause.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../../services/app_services.dart';
import '../../services/send_service.dart';
import '../labels.dart';

/// Shows [message] in a snack bar, replacing any current one.
void showSendError(BuildContext context, String message) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// A button that sends [keyName] of [device].
class RemoteButton extends StatefulWidget {
  /// Creates a button.
  const RemoteButton({
    super.key,
    required this.device,
    required this.keyName,
    this.size = 56,
    this.label,
    this.color,
    this.wide = false,
  });

  /// The remote.
  final SavedDevice device;

  /// Normalized key name.
  final String keyName;

  /// Diameter (or height for wide buttons). Never below 48.
  final double size;

  /// Override for the visible text.
  final String? label;

  /// Accent colour (colour keys). Meaning is never carried by colour alone:
  /// the label is always present.
  final Color? color;

  /// Whether the button is a wide pill.
  final bool wide;

  @override
  State<RemoteButton> createState() => _RemoteButtonState();
}

class _RemoteButtonState extends State<RemoteButton> {
  HoldSession? _hold;
  bool _pulse = false;

  bool get _available => widget.device.keys.containsKey(widget.keyName);

  void _down() {
    if (!_available) return;
    HapticFeedback.lightImpact();
    setState(() => _pulse = true);
    final services = AppScope.of(context);
    final l = AppLocalizations.of(context);
    _hold = services.send.press(
      widget.device,
      widget.keyName,
      onOutcome: (o) {
        if (!mounted) return;
        final msg = outcomeMessage(l, o);
        if (msg != null) {
          HapticFeedback.heavyImpact();
          showSendError(context, msg);
        }
      },
    );
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _pulse = false);
    });
  }

  void _up() {
    _hold?.release();
    _hold = null;
  }

  @override
  void dispose() {
    _hold?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final custom = widget.device.keys[widget.keyName]?.label;
    final text =
        widget.label ?? keyLabel(l, widget.keyName, customLabel: custom);
    final semantic = _available ? text : l.remoteMissingKey(text);
    final icon = widget.label == null ? keyIcon(widget.keyName) : null;
    final size = widget.size < 48 ? 48.0 : widget.size;
    final bg = widget.color ?? scheme.secondaryContainer;
    final fg = widget.color == null
        ? scheme.onSecondaryContainer
        : (ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
              ? Colors.white
              : Colors.black);
    final child = icon != null
        ? Icon(icon, color: fg, size: size * 0.45)
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: fg, fontWeight: FontWeight.w600),
            ),
          );
    return Semantics(
      button: true,
      enabled: _available,
      label: semantic,
      excludeSemantics: true,
      onTap: _available
          ? () {
              _down();
              _up();
            }
          : null,
      child: Opacity(
        opacity: _available ? 1 : 0.38,
        child: Listener(
          onPointerDown: (_) => _down(),
          onPointerUp: (_) => _up(),
          onPointerCancel: (_) => _up(),
          child: AnimatedScale(
            scale: _pulse ? 0.92 : 1,
            duration: const Duration(milliseconds: 90),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              constraints: BoxConstraints(
                minWidth: widget.wide ? size * 2 : size,
                minHeight: size,
              ),
              decoration: BoxDecoration(
                color: _pulse ? scheme.primary.withValues(alpha: 0.35) : bg,
                borderRadius: BorderRadius.circular(
                  widget.wide ? size / 2 : size,
                ),
              ),
              alignment: Alignment.center,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
